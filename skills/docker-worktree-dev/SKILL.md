---
name: docker-worktree-dev
description: Scaffolds a multi-worktree Docker development environment from tested templates — deterministic port allocation, nip.io hostname routing, shared infrastructure with pinned project name, two-network isolation, host nginx reverse proxy, dependency-hash rebuilds, and AI-tool URL injection. Use when setting up isolated Docker dev environments per git branch/worktree, creating a Makefile for worktree port allocation, configuring nip.io hostnames, fixing container-to-container nip.io loopback, or sharing a database across worktrees. Trigger phrases include 'multi-worktree docker', 'worktree dev environment', 'docker port hashing', 'nip.io setup', 'dev environment per branch', 'make dev worktree'. Not for production deployment, CI/CD, or Kubernetes.
---

# Docker Multi-Worktree Dev Environment

Run many git worktree branches at once with isolated containers, unique ports,
nip.io hostnames, and one shared database. This skill ships **tested template
files** in `templates/`; the workflow is copy-then-customize, not
generate-from-scratch — that is what makes the first `make dev` work and keeps
every project on the same battle-tested base instead of rediscovering fixes.

## When to use

- Multiple branches must run simultaneously with per-branch isolation.
- A Docker Compose project where databases/caches are shared across branches.
- Container-to-container or cross-stack calls through nip.io URLs.
- Any project combining `git worktree` with Docker Compose.

## When NOT to use

- Production deployment, CI/CD pipelines, or Kubernetes.
- Single-branch projects that never run two worktrees at once.
- Projects without Docker Compose, or where hostname routing adds nothing.

## Files in this skill

```
docker-worktree-dev/
├── SKILL.md                      # this overview + workflow
├── templates/                    # COPY these into the target project
│   ├── Makefile
│   ├── docker-compose.yml        # per-worktree app services (two networks)
│   ├── docker-compose.infra.yml  # shared DB/cache (pinned project name)
│   ├── docker-compose.override.yml  # optional build-egress fix (gitignored)
│   ├── nginx-vhost.conf          # annotated reference vhost
│   ├── vite.config.snippet.ts    # wires Makefile env into the dev server
│   ├── gitignore.snippet
│   └── ai-instructions.snippet.md
├── scripts/
│   ├── resolve_loopback_url.py   # nip.io loopback → host.docker.internal
│   └── check_host_deps.sh        # preflight: docker/nginx/ss/nip.io
└── reference/                    # read on demand
    ├── infrastructure.md         # sharing, naming, volumes, healthchecks, .env
    ├── networking.md             # two networks, nip.io, loopback, cross-stack
    ├── port-allocation.md        # hash + probe algorithm, limits
    └── troubleshooting.md        # symptom → cause → fix
```

## Prerequisites

git worktree · Docker + Compose v2 · host nginx · nip.io (or `/etc/hosts`) ·
Linux `ss` (adapt to `lsof` on macOS). Run `scripts/check_host_deps.sh` to
verify before the first `make dev`.

Quality over speed: get each subsystem (infra, ports, networking, nginx,
loopback) working independently before declaring success.

## Setup workflow

Copy this checklist and work through it; details are in `reference/`.

```
Setup progress:
- [ ] Step 1: Preflight host deps
- [ ] Step 2: Copy template files
- [ ] Step 3: Customize naming + services
- [ ] Step 4: Wire the frontend dev server
- [ ] Step 5: Bootstrap .env and .gitignore
- [ ] Step 6: Implement the loopback fallback (if needed)
- [ ] Step 7: Inject dev URLs into AI instructions
- [ ] Step 8: First run and verify
```

### Step 1 — Preflight host deps

Run `bash scripts/check_host_deps.sh`. Fix every MISS before continuing
(missing nginx `sites-enabled` include and blocked nip.io are the usual ones).

### Step 2 — Copy template files

Copy into the project root: `Makefile`, `docker-compose.yml`,
`docker-compose.infra.yml`. Copy `docker-compose.override.yml` only if the host
has slow Docker-bridge build egress (see reference/infrastructure.md).

### Step 3 — Customize naming and services

Edit only the `CUSTOMIZE` markers.

- **Makefile:** set `PROJECT_SLUG`; confirm `INFRA_READY_CONTAINER` matches the
  infra `container_name`; replace the infra readiness probe with a real one
  (`pg_isready` / `cqlsh` / `redis-cli ping`); add/remove per-service port
  bases (each base in the probe loop needs a matching `export <SERVICE>_PORT`)
  and the matching hostnames.
- **docker-compose.yml:** set each service's build context/target, internal
  ports, env, and source mount. Keep the **two networks**: `shared` (external)
  for anything reaching the shared DB or `host.docker.internal`; `internal`
  (private) for the per-worktree broker/cache so their service-name DNS can't
  collide with another worktree. Keep the masking volumes
  (`/app/node_modules`, `/app/.venv`, …), healthchecks,
  `depends_on: service_healthy`, and `extra_hosts`.
- **docker-compose.infra.yml:** set the DB/cache image and credentials; keep the
  stable `container_name`, `restart: unless-stopped`, and healthcheck. Decide
  share-vs-isolate per service (reference/infrastructure.md).

Do **not** remove these load-bearing fixes (each maps to a past production bug —
see reference/ for the why):

| Keep | Why |
|------|-----|
| Pinned `-p <slug>-infra` in `make infra` | else every worktree gets its own DB |
| Sanitized `COMPOSE_PROJECT_NAME` | paths with uppercase break compose names |
| Two-network topology | else service-name DNS collides across worktrees |
| Masking volumes on bind mounts | else fresh checkout has no node_modules |
| `restart: unless-stopped` on infra | else reboot hangs `make infra` forever |
| `--remove-orphans` + volume reclaim in `down` | rename safety + disk bloat |
| `APP_URL=...${API_HOST}` single `$` | `$$` breaks OAuth redirects |
| nginx `client_max_body_size` + timeouts | uploads (413) and SSE streams |

### Step 4 — Wire the frontend dev server

Merge `templates/vite.config.snippet.ts` (`allowedHosts`, `/api` proxy with
`ws: true`, `watch.usePolling`) into the project's `vite.config.ts`, or apply
the equivalent for your framework. Without this the Makefile's exported
`VITE_*` vars wire to nothing: the host is rejected, the proxy is dead, HMR is
silent. (See reference/networking.md and reference/infrastructure.md.)

### Step 5 — Bootstrap .env and .gitignore

Append `templates/gitignore.snippet` to `.gitignore`. If the API uses
`env_file`, create `api/.env.example` (all keys, safe dev defaults) and
`cp api/.env.example api/.env`. Never commit `.env` or
`docker-compose.override.yml`.

### Step 6 — Implement the loopback fallback (if needed)

If any container calls another container/stack through a nip.io URL, route those
calls through `scripts/resolve_loopback_url.py` (or port its logic) and keep
`extra_hosts: ["host.docker.internal:host-gateway"]` on the service. For a
second compose stack, reach it via `host.docker.internal:<published-port>` and
keep any shared issuer/URL byte-for-byte identical across stacks
(reference/networking.md).

### Step 7 — Inject dev URLs into AI instructions

`make dev` writes `.dev-urls` (and `make ports` prints them). Paste
`templates/ai-instructions.snippet.md` into the project's `CLAUDE.md` /
`AGENTS.md` / `.cursorrules` so AI tools read the real per-worktree URLs instead
of guessing `localhost:PORT`.

### Step 8 — First run and verify

```bash
make infra      # one shared infra stack (pinned project), waits for readiness
make dev        # this worktree: build/up, nginx vhost, .dev-urls
make ports      # confirm host + nip.io URLs
```

Verify, in order: exactly one shared infra container
(`docker ps | grep shared`); this worktree on its own `*_internal` network
(`docker network ls`); the frontend host loads; the API host answers; HMR
reloads on a source edit; if applicable, a container-to-container nip.io call
succeeds. Then `make down` cleans containers, anon volumes, and the vhost.

## Lifecycle

```bash
git worktree add ../my-project-feature-x feature/x
cd ../my-project-feature-x
make infra      # only needed once across all worktrees
make dev        # prints Frontend/API nip.io URLs; writes .dev-urls
make ps         # status (worktree + infra)
make down       # stop + reclaim volumes + remove vhost
cd ../my-project && git worktree remove ../my-project-feature-x
```

Always `make down` before `git worktree remove`, or orphan containers linger
(cleanup in reference/troubleshooting.md).

## Language-specific notes

- **Python:** in the dev entrypoint, guard a stale bind-mounted `.venv`
  (`[ -L .venv/bin/python3 ] && [ ! -x .venv/bin/python3 ] && rm -rf .venv && uv sync`).
  Hot-reload workers with `watchfiles` under a dev conditional.
- **Node:** Vite needs `allowedHosts` + polling (Step 4). Hot-reload workers
  with `nodemon`/`tsx --watch` under `NODE_ENV=development`.

## Verifying isolation (quick reference)

```bash
docker ps --format '{{.Names}}' | grep shared        # exactly one infra stack
docker network ls | grep internal                    # one per running worktree
docker ps --format '{{.Names}}' | grep -E 'broker|cache' | sort   # per-worktree
```

Symptom → fix table lives in reference/troubleshooting.md.

## Caveats and known limits

- `.deps-hash` and `.dev-urls` are generated per worktree — gitignored.
- nip.io may be blocked by corporate DNS — use `/etc/hosts` or dnsmasq.
- `extra_hosts` host-gateway is required on Linux (automatic on Docker Desktop).
- Port offset space is 100 — past ~20 simultaneous worktrees, widen the modulo
  (reference/port-allocation.md).
- Shared DB means migration ordering matters across branches — coordinate, or
  isolate the DB per worktree for heavy schema work.
- Port allocation has a small TOCTOU window — `make down && make dev` re-checks.

## Iterating on this skill

These templates encode fixes from production multi-worktree setups. When a new
worktree setup surfaces a fresh failure mode, fix it **in `templates/` here**
(and note the why in `reference/`) so the next project inherits it — rather than
patching one project's copy and letting the templates drift.
