# Infrastructure: shared vs per-worktree, naming, volumes, builds

## Contents

- Project-name sanitization
- Pinned shared-infra project name
- Share vs isolate decision
- Restart policy (mandatory)
- Healthchecks, ordered startup, worker heartbeat
- node_modules / .venv masking volumes
- Dependency-hash auto-rebuild and volume reclaim
- Build-time egress override
- .env bootstrapping

## Project-name sanitization

`COMPOSE_PROJECT_NAME` must be lowercase alphanumeric plus hyphen/underscore and
start with an alphanumeric. Worktrees often live under paths containing
uppercase (e.g. `~/Projects/...`), which yields an invalid project name and a
hard compose failure. The Makefile builds it from `parent-dir + worktree-name`
then sanitizes: lowercase, map invalid chars → `-`, strip leading non-alnum.

## Pinned shared-infra project name

`make infra` runs the infra compose under a **fixed** `-p <slug>-infra`.
This is the single most important correctness fix. If infra is brought up while
`COMPOSE_PROJECT_NAME` is exported (no `-p`), Compose namespaces it under the
*worktree's* project name, so **every worktree spins up its own database** and
the "shared infrastructure" premise silently breaks. Pinning `-p` plus a stable
`container_name` keeps one infra stack for all worktrees and lets the Makefile
readiness probe + "already running" guard target the container by name.

## Share vs isolate decision

**Share** (in `docker-compose.infra.yml`, pinned project):
- Databases — same dataset across branches, consistent migrations.
- Caches — *optional*: shared is simpler but can leak state across branches.
  If cross-branch cache poisoning bites, move the cache into
  `docker-compose.yml` on the `internal` network instead.

**Isolate** (in each worktree's `docker-compose.yml`):
- App servers / frontends — run branch-specific code.
- Brokers (RabbitMQ/Kafka) — prevent cross-branch queue contamination.
- Workers — must run branch code.

Need per-branch DB isolation? Move the DB service into `docker-compose.yml`.

## Restart policy (MANDATORY)

Every infra service must declare `restart: unless-stopped`. Without it, a host
reboot leaves infra containers `Exited`; the `make infra` readiness loop then
polls a dead container forever, and `docker compose up -d` refuses to recreate a
dead container that still owns `container_name`. No worktree owns infra, so
nothing recovers it automatically. Immediate recovery:
`docker rm <dead> && make infra`.

## Healthchecks, ordered startup, worker heartbeat

Ship healthchecks on every service and gate dependents with
`depends_on: { condition: service_healthy }`, so workers don't crash-loop until
the broker is up and `make dev` doesn't race a cold database.

Workers have no port to probe — use a **heartbeat file**: the worker touches
`/tmp/worker.heartbeat` each loop and the healthcheck fails if it goes stale:

```yaml
healthcheck:
  test: ["CMD-SHELL", "[ -f /tmp/worker.heartbeat ] && [ \"$$(($$(date +%s) - $$(cat /tmp/worker.heartbeat)))\" -lt 60 ]"]
stop_grace_period: 30s   # let in-flight jobs drain on shutdown
```

## node_modules / .venv masking volumes

Bind-mounting host source (`./front:/app/front`) shadows the image's installed
dependencies with the host directory, so a fresh checkout starts with
missing/foreign `node_modules`. Declare anonymous masking volumes on the mount
points (a workspace monorepo needs one per package root):

```yaml
volumes:
  - ./front:/app/front
  - /app/node_modules
  - /app/front/node_modules
```

`-V` only **recreates existing** anonymous volumes; it does not create masks.

## Dependency-hash auto-rebuild and volume reclaim

`make dev` md5-hashes the tracked lock/manifest files and, on change, rebuilds
with `-V` (refreshing the anon dep volumes), else just `up -d`. Each `-V`
orphans the previous anonymous volume; across many worktrees this reaches
gigabytes. `make down` therefore inspects the stack's anonymous mounts, runs
`docker compose down --remove-orphans`, then removes those volumes.
`--remove-orphans` also clears stale containers left after a service rename
(which otherwise block `up`).

## Build-time egress override

Some hosts have slow egress on Docker's default bridge, so dependency installs
stall/time out during builds while the host network is fast. The optional,
gitignored `docker-compose.override.yml` sets `build.network: host` per service
(build steps only; runtime networking unaffected). docker compose auto-loads it.
Remove it once the bridge egress is fixed.

## .env bootstrapping

The API typically loads `env_file: ./api/.env` (secrets, mock-mode toggles,
OAuth config). Commit a tracked `.env.example` documenting every key with safe
dev defaults; the real `.env` (and `docker-compose.override.yml`) stay
gitignored (see `templates/gitignore.snippet`). First-run setup:
`cp api/.env.example api/.env` then fill required secrets.
