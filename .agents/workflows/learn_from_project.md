# Kamal Deploy Skill Training Workflow

You are improving the Kamal Deploy Skill by using a real project as a new deployment test case.

There are two repositories:

- Skill repository: `{{SKILL_REPO}}`
- Target project: `{{TARGET_PROJECT}}`

The target project DOES NOT currently have a Kamal deployment.

This is important.

You are not learning an existing Kamal configuration from the target project.

Instead, you must:

1. understand the target project's deployment requirements;
2. determine which of those requirements the current Kamal Deploy Skill does not adequately support;
3. improve the Skill with generalized knowledge;
4. use the improved Skill to create a Kamal deployment for the target project;
5. validate the resulting deployment;
6. use failures or shortcomings discovered during validation to improve the Skill again.

The final goal is BOTH:

- a better reusable Kamal Deploy Skill;
- a correct Kamal deployment for the target project.

---

# Fundamental rule

Treat the target project as a deployment test case, not as a source of project-specific instructions to blindly copy into the Skill.

Never add project-specific values to the reusable Skill.

Examples of project-specific information that must NOT become Skill knowledge:

- domains;
- IP addresses;
- credentials;
- project names;
- container names that only make sense in this project;
- arbitrary environment variables;
- paths unique to this repository;
- business-specific processes.

Instead, extract the general deployment pattern behind them.

For example:

BAD:

> Bilko needs Redis on port 6379.

GOOD:

> Applications using Redis as an internal dependency should normally configure Redis as a Kamal accessory or external service and expose it only through the private deployment network unless external access is explicitly required.

---

# Phase 1 — Read-only target project discovery

Do not modify either repository yet.

Analyze the target project thoroughly.

Determine:

- repository structure;
- whether it is a monorepo;
- applications/services contained in it;
- languages and frameworks;
- runtime versions;
- package managers;
- build systems;
- production build commands;
- application start commands;
- Dockerfiles;
- Docker Compose configuration;
- development container configuration;
- exposed/listening ports;
- health endpoints;
- databases;
- caches;
- queues;
- workers;
- scheduled/background jobs;
- migrations;
- persistent storage;
- uploads;
- external services;
- internal service-to-service networking;
- WebSockets;
- asset building;
- static asset serving;
- system packages;
- native dependencies;
- required environment variables;
- secrets;
- build-time variables;
- runtime variables;
- graceful shutdown requirements;
- deployment ordering requirements;
- reverse proxy requirements;
- TLS requirements;
- scaling expectations discoverable from the codebase.

Inspect actual implementation rather than relying only on README documentation.

README files may be outdated.

When useful, inspect:

- dependency manifests;
- lock files;
- Docker configuration;
- CI workflows;
- `.env.example`;
- process definitions;
- framework configuration;
- startup scripts;
- database configuration;
- source code where runtime behavior cannot otherwise be determined.

Produce a deployment model of the application.

Store temporary analysis under:

`.agents/runs/{{TARGET_NAME}}/`

Do not put temporary observations into permanent Skill documentation.

---

# Phase 2 — Evaluate the existing Skill

Read the complete Kamal Deploy Skill.

Compare the deployment model discovered in Phase 1 with the capabilities and instructions currently provided by the Skill.

Create a gap analysis.

For every deployment requirement classify it as:

- ALREADY_SUPPORTED
- SUPPORTED_BUT_INCOMPLETE
- UNSUPPORTED
- PROJECT_SPECIFIC
- UNCERTAIN

Pay special attention to assumptions in the existing Skill.

For example, determine whether the Skill incorrectly assumes:

- one application per repository;
- one Docker image;
- one HTTP service;
- Rails;
- Node;
- a single Dockerfile;
- no workers;
- no persistent storage;
- no non-HTTP services;
- no multi-stage builds;
- no monorepos.

Do not change the Skill just because this project happens to implement something differently.

Only change the Skill when there is a reusable deployment lesson.

---

# Phase 3 — Design Skill improvements

For each reusable gap, determine the correct generalized Kamal deployment pattern.

Prefer authoritative documentation and actual tool behavior over assumptions.

If a deployment behavior is uncertain, verify it before turning it into Skill guidance.

New Skill knowledge should describe:

1. how to detect the situation;
2. why it matters;
3. how Kamal should represent it;
4. what configuration is required;
5. how to validate it;
6. common failure modes.

Prefer capability-oriented instructions over framework-name-only instructions.

For example, prefer:

> Applications with a separate background worker process...

over:

> Django projects...

when the underlying deployment rule applies to multiple frameworks.

Framework-specific instructions are appropriate when the framework genuinely requires special behavior.

---

# Phase 4 — Improve the Skill

Now modify the Kamal Deploy Skill.

Keep `SKILL.md` focused and navigable.

Move detailed stack-specific information into appropriate references when necessary.

A preferred structure is:

- `SKILL.md`
- `references/stacks/`
- `references/patterns/`
- `tests/fixtures/`

Examples:

`references/stacks/nextjs.md`

`references/stacks/rails.md`

`references/patterns/background-workers.md`

`references/patterns/monorepo.md`

`references/patterns/persistent-storage.md`

Do not create unnecessary files merely to satisfy this structure.

Use the existing Skill architecture when it already has a suitable organization.

---

# Regression protection

Every important generalized behavior learned from the target project should have some form of regression protection.

When practical, create a minimal synthetic fixture representing the newly supported deployment pattern.

Do NOT copy the entire target project into the Skill repository.

For example, if the new lesson is:

"monorepo containing a Next.js frontend and a separate API"

create the smallest useful fixture representing that structure.

Tests or evaluation scenarios should verify that the Skill recognizes the architecture and produces the expected deployment strategy.

Existing supported stacks must continue working.

---

# Phase 5 — Re-read the improved Skill

After modifying the Skill, stop using assumptions gathered during the initial analysis.

Re-read the resulting Skill as if you were a fresh deployment agent.

The next phase must be performed according to the UPDATED Skill.

This separation is important because we want to test whether the knowledge was actually transferred into the Skill.

---

# Phase 6 — Apply the Skill to the target project

Now use the updated Kamal Deploy Skill to add deployment support to:

`{{TARGET_PROJECT}}`

Create the appropriate production deployment configuration.

Depending on the project this may include:

- Dockerfile changes;
- additional Dockerfiles;
- `.dockerignore`;
- Kamal configuration;
- destinations;
- roles;
- accessories;
- hooks;
- healthchecks;
- environment configuration;
- secrets configuration;
- build configuration;
- volumes;
- proxy configuration;
- worker configuration;
- deployment documentation.

Follow existing conventions in the target repository.

Do not redesign unrelated application architecture.

Do not change application behavior unless necessary for correct containerization or deployment.

Never commit secrets.

---

# Phase 7 — Validation

Validate as much of the deployment as possible.

At minimum validate:

- configuration syntax;
- Kamal configuration;
- Docker image builds;
- required runtime commands;
- service startup;
- expected ports;
- health checks;
- migrations;
- worker startup where applicable;
- container networking assumptions;
- required environment variables.

If an isolated local or staging verification environment exists, use it.

Do NOT deploy to production unless production deployment has explicitly been requested and authorization/infrastructure are available.

Do not claim the deployment works simply because files were generated successfully.

A successful configuration generation is not a successful deployment validation.

---

# Phase 8 — Feedback loop

If validation reveals problems, diagnose each failure and classify it.

## GENERIC_SKILL_FAILURE

The Skill produced incorrect or incomplete guidance that could affect other projects.

Action:

1. fix the Skill;
2. add or improve regression coverage;
3. re-read the Skill;
4. regenerate or fix the target deployment;
5. validate again.

## PROJECT_SPECIFIC_FAILURE

The Skill guidance is correct but this application has an unusual project-specific requirement.

Action:

Fix the target repository only.

Do not pollute the Skill with project-specific behavior.

## INFRASTRUCTURE_FAILURE

Examples:

- missing credentials;
- inaccessible server;
- DNS issue;
- registry permissions;
- firewall;
- unavailable external service.

Action:

Report the infrastructure problem.

Do not encode an infrastructure accident as reusable Skill knowledge.

## UNKNOWN

Investigate further before modifying the Skill.

---

# Iteration rule

Repeat the feedback loop until:

- the deployment configuration passes all feasible validation;
- no newly discovered generic Skill defects remain;
- remaining blockers, if any, are external and clearly documented.

Do not repeatedly patch symptoms.

When a failure exposes an incorrect abstraction in the Skill, fix the abstraction.

---

# Change isolation

Maintain a clear separation between changes.

The Skill repository should contain:

- reusable knowledge;
- reusable templates;
- reusable detection logic;
- reusable tests/fixtures.

The target repository should contain:

- this project's Docker/Kamal configuration;
- project-specific deployment documentation;
- project-specific environment definitions.

Never mix the two.

---

# Final review

Before finishing, review all Skill changes and ask:

"Would this instruction still make sense if the original target project disappeared?"

If the answer is no, the instruction is probably too project-specific.

Also ask:

"Could this change make an already-supported deployment worse?"

If yes, add appropriate regression protection or redesign the change.

---

# Final output

Provide a report containing:

## Target architecture

Short description of the deployment architecture discovered.

## Skill gaps discovered

What the Skill could not previously handle correctly.

## Skill improvements

What reusable knowledge was added or changed.

## Target deployment changes

What was added to the target project.

## Validation performed

Exact checks actually performed and their results.

Clearly distinguish:

- verified;
- inferred;
- not tested.

## Feedback-driven corrections

Problems discovered after applying the updated Skill and how they changed the Skill.

## Remaining limitations

Anything that could not be verified.

## Repository changes

List changes separately for:

- Kamal Deploy Skill;
- target project.

The process is complete only when the target project has served as a genuine regression/evaluation case for the improved Skill rather than merely receiving a one-off deployment configuration.
