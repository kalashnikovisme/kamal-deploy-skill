# Kamal Commands Reference

## Core Commands

| Command | Description |
|---------|-------------|
| `kamal setup` | First-time setup: install Docker on servers, authenticate registry, build and deploy the app |
| `kamal deploy` | Deploy a new version of the application |
| `kamal redeploy` | Deploy without full bootstrap (faster, skips server provisioning) |
| `kamal rollback [VERSION]` | Roll back to a previous version (use `kamal audit` to find version hashes) |

## Application Commands

| Command | Description |
|---------|-------------|
| `kamal app details` | Show running container details |
| `kamal app logs` | Show application logs |
| `kamal app logs --follow` | Stream application logs |
| `kamal app logs --lines 100` | Show last 100 log lines |
| `kamal app restart` | Restart app containers |
| `kamal app stop` | Stop app containers |
| `kamal app start` | Start stopped containers |
| `kamal app exec --reuse 'command'` | Execute a command in a running container |
| `kamal app exec -i --reuse 'bash'` | Open an interactive shell in a running container |
| `kamal app boot` | Boot app containers |
| `kamal app remove` | Remove app containers |

## Build Commands

| Command | Description |
|---------|-------------|
| `kamal build push` | Build and push the image to the registry |
| `kamal build pull` | Pull the latest image from the registry |
| `kamal build details` | Show build details |

## Accessory Commands

| Command | Description |
|---------|-------------|
| `kamal accessory boot all` | Boot all accessories |
| `kamal accessory boot postgres` | Boot a specific accessory |
| `kamal accessory details all` | Show all accessory details |
| `kamal accessory logs postgres` | Show logs for an accessory |
| `kamal accessory exec postgres -- psql -U app` | Execute a command in an accessory container |
| `kamal accessory restart postgres` | Restart an accessory |
| `kamal accessory remove postgres` | Remove an accessory |

## Proxy Commands

| Command | Description |
|---------|-------------|
| `kamal proxy boot` | Boot kamal-proxy on servers |
| `kamal proxy details` | Show proxy container details |
| `kamal proxy logs` | Show proxy logs |
| `kamal proxy restart` | Restart the proxy |
| `kamal proxy remove` | Remove the proxy |

## Registry Commands

| Command | Description |
|---------|-------------|
| `kamal registry login` | Log in to the image registry |
| `kamal registry logout` | Log out from the registry |

## Server Commands

| Command | Description |
|---------|-------------|
| `kamal server bootstrap` | Bootstrap servers (install Docker) |

## Audit and Diagnostics

| Command | Description |
|---------|-------------|
| `kamal audit` | Show deployment audit log (versions, timestamps) |
| `kamal details` | Show details for all containers (app + accessories + proxy) |
| `kamal config` | Show the resolved configuration (WARNING: shows secrets) |
| `kamal version` | Show installed Kamal version |

## Lock Commands

| Command | Description |
|---------|-------------|
| `kamal lock acquire` | Manually acquire the deploy lock |
| `kamal lock release` | Release a stuck deploy lock |
| `kamal lock status` | Show current lock status |

## Secrets Commands

| Command | Description |
|---------|-------------|
| `kamal secrets fetch` | Fetch and display secrets (for debugging) |
| `kamal secrets print` | Print secrets as environment variables |

## Destination Flag

Append `-d <destination>` to any command to target a specific destination:

```bash
kamal deploy -d staging
kamal app logs -d production
kamal rollback abc123 -d staging
```

## Common Workflows

### First deployment

```bash
# 1. Ensure .kamal/secrets is populated
# 2. Run setup (provisions servers + deploys)
kamal setup

# For staging:
kamal setup -d staging
```

### Subsequent deployments

```bash
kamal deploy
# Or for staging:
kamal deploy -d staging
```

### Emergency rollback

```bash
# Find the version to roll back to:
kamal audit

# Roll back:
kamal rollback <VERSION>
```

### Access production console / shell

```bash
# Interactive shell:
kamal app exec -i --reuse 'bash'

# Run a one-off command:
kamal app exec --reuse 'env'
```

### View production logs live

```bash
kamal app logs --follow
```

### Restart without redeploying

```bash
kamal app restart
```

### Boot database on first setup

```bash
kamal accessory boot postgres
kamal accessory boot redis
```
