# Java / Spring Boot Deployment Recipe

This recipe covers deployment of Java applications via Kamal. Applies to: Spring Boot (Maven or Gradle), Quarkus, Micronaut, and generic Java web applications.

## 1. Inspect the Project

Detect build tool and framework:
- `pom.xml` → Maven
- `build.gradle` or `build.gradle.kts` → Gradle

Read the build file to determine:
- Java version: `<java.version>` in `pom.xml` or `sourceCompatibility` / `java.toolchain.languageVersion` in Gradle
- Framework: Spring Boot (`org.springframework.boot` plugin), Quarkus (`io.quarkus`), Micronaut, etc.
- Packaging: JAR (typical for Spring Boot) or WAR

Also check:
- Is there an existing `Dockerfile`? Inspect before creating.
- Does the project use Spring Boot Actuator? → health endpoint at `/actuator/health`
- Server port: `server.port` in `application.properties` / `application.yml` (defaults to `8080`)

## 2. Determine Health Check Path

| Framework | Default health path | Notes |
|-----------|-------------------|-------|
| Spring Boot + Actuator | `/actuator/health` | Include `spring-boot-starter-actuator` |
| Spring Boot (no Actuator) | `/health` | Add a simple controller |
| Quarkus | `/q/health/live` | Quarkus Health extension |
| Micronaut | `/health` | Micronaut Management module |

If Spring Boot Actuator is not present, instruct the user to add it or add a minimal health controller:

```java
@RestController
public class HealthController {
    @GetMapping("/health")
    public ResponseEntity<Map<String, String>> health() {
        return ResponseEntity.ok(Map.of("status", "ok"));
    }
}
```

For Spring Boot Actuator, expose the health endpoint in `application.properties`:

```properties
management.endpoints.web.exposure.include=health
management.endpoint.health.show-details=never
```

## 3. Determine Port

Default: `8080`. Check `server.port` in `src/main/resources/application.properties` or `application.yml`.

## 4. Create Dockerfile

Check for an existing `Dockerfile` first.

### Spring Boot (Maven, JAR packaging)

```dockerfile
FROM eclipse-temurin:21-jdk-alpine AS builder
WORKDIR /app
COPY mvnw ./
COPY .mvn .mvn
COPY pom.xml ./
RUN ./mvnw dependency:go-offline -B
COPY src ./src
RUN ./mvnw package -DskipTests -B

FROM eclipse-temurin:21-jre-alpine AS runner
WORKDIR /app
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
COPY --from=builder /app/target/*.jar app.jar
USER appuser
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

### Spring Boot (Gradle, JAR packaging)

```dockerfile
FROM eclipse-temurin:21-jdk-alpine AS builder
WORKDIR /app
COPY gradlew ./
COPY gradle gradle
COPY build.gradle* settings.gradle* ./
RUN ./gradlew dependencies --no-daemon
COPY src ./src
RUN ./gradlew bootJar --no-daemon -x test

FROM eclipse-temurin:21-jre-alpine AS runner
WORKDIR /app
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
COPY --from=builder /app/build/libs/*.jar app.jar
USER appuser
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

### Spring Boot with layered JAR (faster rebuilds)

Add to `pom.xml` Spring Boot plugin config:

```xml
<configuration>
  <layers>
    <enabled>true</enabled>
  </layers>
</configuration>
```

Then use a layered Dockerfile:

```dockerfile
FROM eclipse-temurin:21-jdk-alpine AS builder
WORKDIR /app
COPY mvnw .mvn* pom.xml ./
RUN ./mvnw dependency:go-offline -B
COPY src ./src
RUN ./mvnw package -DskipTests -B
RUN java -Djarmode=layertools -jar target/*.jar extract --destination target/extracted

FROM eclipse-temurin:21-jre-alpine AS runner
WORKDIR /app
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
COPY --from=builder /app/target/extracted/dependencies/ ./
COPY --from=builder /app/target/extracted/spring-boot-loader/ ./
COPY --from=builder /app/target/extracted/snapshot-dependencies/ ./
COPY --from=builder /app/target/extracted/application/ ./
USER appuser
EXPOSE 8080
ENTRYPOINT ["java", "org.springframework.boot.loader.launch.JarLauncher"]
```

## 5. Create config/deploy.yml

```yaml
service: <APP_NAME>
image: <REGISTRY_USER>/<APP_NAME>

servers:
  web:
    hosts:
      - <SERVER_IP>
    proxy:
      ssl: true
      host: <DOMAIN>
      app_port: 8080
      healthcheck:
        path: /actuator/health
        interval: 5
        timeout: 10

registry:
  username: <REGISTRY_USER>
  password:
    - KAMAL_REGISTRY_PASSWORD

env:
  clear:
    SPRING_PROFILES_ACTIVE: production
    SERVER_PORT: "8080"
    JAVA_OPTS: "-Xmx512m -Xms256m"
  secret:
    - SPRING_DATASOURCE_PASSWORD
    - SPRING_DATASOURCE_URL
    - JWT_SECRET

builder:
  arch: amd64

# accessories:
#   postgres:
#     image: postgres:16
#     host: <SERVER_IP>
#     port: "127.0.0.1:5432:5432"
#     env:
#       clear:
#         POSTGRES_USER: app
#         POSTGRES_DB: <APP_NAME>_production
#       secret:
#         - POSTGRES_PASSWORD
#     directories:
#       - postgres-data:/var/lib/postgresql/data
#
#   redis:
#     image: redis:7-alpine
#     host: <SERVER_IP>
#     port: "127.0.0.1:6379:6379"
#     directories:
#       - redis-data:/data
```

Adjust `healthcheck.path` to `/health` if not using Actuator.
Increase `healthcheck.timeout` if the JVM startup time is slow (Spring Boot can take 10-30s to start).

## 6. Create .kamal/secrets

```bash
# .kamal/secrets
# Load from environment. NEVER commit actual values.

KAMAL_REGISTRY_PASSWORD=$KAMAL_REGISTRY_PASSWORD
SPRING_DATASOURCE_PASSWORD=$SPRING_DATASOURCE_PASSWORD
SPRING_DATASOURCE_URL=$SPRING_DATASOURCE_URL
# JWT_SECRET=$JWT_SECRET
# POSTGRES_PASSWORD=$POSTGRES_PASSWORD
```

Add to `.gitignore`:

```
.kamal/secrets
.kamal/secrets-common
.kamal/secrets.*
```

## 7. Database Migrations

Spring Boot with Flyway or Liquibase runs migrations automatically on startup if configured. Verify:

**Flyway** (`application.properties`):

```properties
spring.flyway.enabled=true
spring.flyway.locations=classpath:db/migration
```

**Liquibase** (`application.properties`):

```properties
spring.liquibase.enabled=true
spring.liquibase.change-log=classpath:db/changelog/db.changelog-master.yaml
```

If using auto-migration, no deploy hook is needed. If running migrations separately, create `.kamal/hooks/pre-deploy`:

```bash
#!/bin/bash
set -e
kamal app exec --reuse "java -jar app.jar --spring.flyway.enabled=true --app.skip-startup=true"
```

This approach depends on the specific project setup. For most Spring Boot projects with Flyway/Liquibase, auto-migration on startup is the standard approach.

## 8. Stack-Specific Caveats

- **JVM startup time**: Spring Boot can take 15-30 seconds to start. Set `readiness_delay` in `deploy.yml` accordingly (default is 7s, which may be too low):
  ```yaml
  readiness_delay: 20
  ```
- **Memory**: Containers need enough memory for the JVM. A minimal Spring Boot app needs ~256MB heap. Set `JAVA_OPTS: "-Xmx512m -Xms256m"` and ensure the server has sufficient RAM.
- **GraalVM native image**: For very fast startup, consider GraalVM native compilation. The Dockerfile changes significantly — use `FROM ghcr.io/graalvm/native-image:21` as the builder and `FROM alpine:3.20` as the runner.
- **Java version**: Match Java version in Dockerfile to project requirements. Use `eclipse-temurin` as it is well-maintained and available on Alpine.
- **Maven wrapper**: Commit `mvnw` and `.mvn/` to version control so Docker builds don't need Maven installed.
- **Gradle wrapper**: Commit `gradlew` and `gradle/` to version control.
- **Quarkus**: Quarkus has its own fast-startup JVM mode and native mode. For native, the Dockerfile changes substantially — use the Quarkus container image guide.
