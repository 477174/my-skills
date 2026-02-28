---
name: docker-worktree-dev
description: Multi-worktree Docker dev environment setup with automatic port isolation, nip.io hostname routing, shared infrastructure, and nginx reverse proxy. Use when setting up isolated Docker dev branches, creating worktree port allocation, configuring nip.io hostnames for dev, or handling container-to-container nip.io loopback issues. Trigger phrases include 'multi-worktree docker', 'worktree dev environment', 'docker port hashing', 'nip.io setup', 'dev environment per branch', 'docker branch isolation', 'worktree make dev'. Do NOT use for production deployment, CI/CD, or Kubernetes.
---

# Docker Multi-Worktree Dev Environment

Run multiple git worktree branches simultaneously with isolated Docker containers, unique ports, and nip.io hostnames.

## When to Use This

- Setting up dev environments where multiple branches must run simultaneously
- Need per-branch port isolation combined with hostname routing
- Docker Compose projects with shared databases across branches
- Container-to-container calls through nip.io URLs
- Any project that uses `git worktree` and Docker Compose together

## When NOT to Use This

- Production deployment, CI/CD pipelines, or Kubernetes orchestration
- Single-developer projects that never run multiple branches simultaneously
- Projects without Docker Compose
- Environments where hostname-based routing is unnecessary (single service)

## Prerequisites

- **git worktree**: For creating isolated working directories per branch
- **Docker + Docker Compose**: Container orchestration (v2+ recommended)
- **nginx**: Host-level reverse proxy for hostname routing
- **nip.io**: Wildcard DNS service (or manual `/etc/hosts` entries)
- **Linux**: `ss` command for port detection (adapt for macOS with `lsof`)

## Performance Notes

Take your time implementing this. Quality over speed. Do not skip validation steps. Verify port allocation, nginx routing, and container connectivity before declaring success. Each subsystem (ports, hostnames, nginx, loopback) must work independently before combining.

## Core Concepts

- **Git worktrees** create isolated working directories — each worktree is a full checkout at a different branch, sharing the same `.git` object store
- **Each worktree gets unique port offsets** via a deterministic hash of its directory path, ensuring no collisions between simultaneously running branches
- **nip.io provides wildcard DNS routing** — any subdomain of `<ip>.nip.io` resolves to that IP, eliminating manual `/etc/hosts` management
- **nginx on the host proxies by hostname** — a vhost per worktree routes `project-branch-service.<ip>.nip.io` to the correct `localhost:<port>`
- **Databases are shared across worktrees** via a separate infrastructure compose file and external Docker network — avoids data duplication and keeps migrations consistent
- **App servers are isolated per worktree** — each branch gets its own frontend, API, worker, and message broker containers
- **Loopback fallback is required** for container-to-container nip.io calls — inside a container, nip.io resolves to `127.0.0.1` (the container itself), so outbound calls must be rewritten to `host.docker.internal`

## Instructions

### 1. Branch Name Sanitization

Normalize the branch name for Docker-safe usage (compose project names, container names, network aliases):

```bash
# Convert branch name to Docker-safe format
BRANCH_SAFE=$(echo "${BRANCH}" | tr '/' '-' | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]//g')
```

Rules: lowercase only, hyphens for separators, strip all characters except `[a-z0-9-]`. Slashes (from `feature/xyz` branches) become hyphens.

### 2. Port Allocation Algorithm

The core algorithm hashes the worktree directory path to produce a deterministic port offset, then performs linear probing to avoid collisions with already-bound ports.

```makefile
# CUSTOMIZE: Define your service ports (base_port + offset for each)
# Add or remove port checks based on your services
_PORT_OFFSET := $(shell \
	pref=$$(( $$(printf '%s' "$(CURDIR)" | cksum | cut -d' ' -f1 | head -c4) % 100 )); \
	used=$$(ss -tln 2>/dev/null); \
	for i in $$(seq 0 99); do \
		o=$$(( (pref + i) % 100 )); \
		fp=$$(( 3000 + o )); ap=$$(( 8000 + o )); \
		if ! echo "$$used" | grep -qE ":$$fp\s" \
		&& ! echo "$$used" | grep -qE ":$$ap\s"; then \
			echo $$o; exit 0; \
		fi; \
	done; \
	echo $$pref)

# CUSTOMIZE: Export one variable per service port
# Add more exports for additional services (e.g., message brokers, admin panels)
export FRONTEND_PORT := $(shell echo $$(( 3000 + $(_PORT_OFFSET) )))
export API_PORT      := $(shell echo $$(( 8000 + $(_PORT_OFFSET) )))
```

**How it works:**

1. `cksum` hashes the full `$(CURDIR)` path — same directory always produces same initial preference
2. `% 100` constrains to offset range 0–99, giving port ranges like 3000–3099 and 8000–8099
3. `ss -tln` captures all currently listening TCP ports
4. Linear probing: if preferred offset is taken, try `(pref + 1) % 100`, `(pref + 2) % 100`, etc.
5. Maximum 100 probes before falling back to original preference
6. **Recommended base ranges**: 3000–3099 (frontend), 8000–8099 (API), 5672–5771 (AMQP), 15672–15771 (management UIs)

**To add more services**, add additional port checks in the `if` block and export lines. For example, adding a message broker:

```makefile
# Inside the collision check, add:
rp=$$(( 5672 + o )); rmp=$$(( 15672 + o )); \
# ... && ! echo "$$used" | grep -qE ":$$rp\s" \
# ... && ! echo "$$used" | grep -qE ":$$rmp\s"; then \

# Additional exports:
export BROKER_PORT     := $(shell echo $$(( 5672 + $(_PORT_OFFSET) )))
export BROKER_MGMT_PORT := $(shell echo $$(( 15672 + $(_PORT_OFFSET) )))
```

### 3. nip.io Hostname Pattern

Generate predictable, human-readable hostnames per worktree per service:

```makefile
# Derive compose project name from parent directory + worktree name
PARENT_DIR := $(notdir $(patsubst %/,%,$(dir $(CURDIR))))
export COMPOSE_PROJECT_NAME := $(PARENT_DIR)-$(notdir $(CURDIR))

# Detect server IP (handles WSL vs native Linux)
SERVER_IP := $(shell grep -q microsoft /proc/version 2>/dev/null \
	&& echo 127.0.0.1 \
	|| ip route get 1.1.1.1 2>/dev/null | awk '{print $$7; exit}')

# CUSTOMIZE: One hostname per service
export FRONTEND_HOST := $(COMPOSE_PROJECT_NAME)-frontend.$(SERVER_IP).nip.io
export API_HOST      := $(COMPOSE_PROJECT_NAME)-api.$(SERVER_IP).nip.io
```

**Result**: A worktree at `/code/myproject/feature-auth` produces hostnames like `myproject-feature-auth-frontend.192.168.1.50.nip.io`.

### 4. nip.io Loopback Fallback (CRITICAL)

**Problem**: nip.io resolves to the embedded IP (e.g., `127.0.0.1`). Inside a Docker container, `127.0.0.1` means the container itself — not the host. Any container-to-container HTTP call through a nip.io URL will fail silently or connect to the wrong service.

**Language-agnostic pseudocode:**

```
function resolve_loopback_url(url):
    hostname = parse_url(url).hostname
    resolved_ip = dns_resolve(hostname)
    if is_loopback(resolved_ip):
        new_url = replace_hostname(url, "host.docker.internal")
        original_host = hostname  # preserve for Host header
        return new_url, original_host
    return url, null
```

**Python implementation:**

```python
import ipaddress
import socket
from urllib.parse import urlparse, urlunparse


def resolve_loopback_url(url: str) -> tuple[str, str | None]:
    """Detect nip.io loopback and reroute through Docker host gateway.

    Returns (possibly_rewritten_url, original_netloc_or_none).
    When original_netloc is not None, pass it as the Host header.
    """
    parsed = urlparse(url)
    hostname = parsed.hostname
    if not hostname:
        return url, None
    try:
        resolved_ip = socket.gethostbyname(hostname)
        if ipaddress.ip_address(resolved_ip).is_loopback:
            docker_host = parsed._replace(
                netloc=parsed.netloc.replace(hostname, "host.docker.internal")
            )
            return urlunparse(docker_host), parsed.netloc
    except socket.gaierror:
        pass
    return url, None
```

**REQUIREMENT**: Add `extra_hosts` to every service in `docker-compose.yml` that makes outbound HTTP calls through nip.io URLs:

```yaml
extra_hosts:
  - "host.docker.internal:host-gateway"
```

Without this, `host.docker.internal` will not resolve inside the container on Linux. This is automatic on Docker Desktop for macOS/Windows but **must be explicit on Linux**.

### 5. Shared vs Per-Worktree Infrastructure

**SHARE across all worktrees** (via a separate `docker-compose.infra.yml`):
- **Databases**: PostgreSQL, MySQL, Cassandra, MongoDB — avoids data duplication, keeps migrations consistent
- **Caches**: Redis, Memcached — shared session stores and caching layers

**ISOLATE per worktree** (in each worktree's `docker-compose.yml`):
- **App servers**: Frontend, API, GraphQL — branch-specific code changes
- **Message brokers**: RabbitMQ, Kafka — prevent cross-contamination of queues
- **Workers**: Background job processors — must run branch-specific code
- **Frontends**: Dev servers — each branch has its own UI

**Rationale**: Shared databases mean all worktrees see the same data. This is usually desired (test the same dataset across branches). If you need per-branch database isolation, duplicate the database service into each worktree's compose file instead.

### 6. Dependency Hash Auto-Rebuild

Detect when dependency files change and automatically rebuild containers:

```makefile
DEPS_HASH_FILE := .deps-hash

# CUSTOMIZE: List your dependency/lock files
DEPS_FILES := front/package.json api/pyproject.toml $(wildcard front/bun.lock front/yarn.lock api/uv.lock api/poetry.lock)
CURRENT_DEPS_HASH := $(shell cat $(DEPS_FILES) 2>/dev/null | md5sum | cut -d' ' -f1)
STORED_DEPS_HASH  := $(shell cat $(DEPS_HASH_FILE) 2>/dev/null)
```

In the `dev` target, compare hashes and rebuild if different:

```makefile
dev:
	@if [ "$(CURRENT_DEPS_HASH)" != "$(STORED_DEPS_HASH)" ]; then \
		echo "Dependencies changed, rebuilding..."; \
		docker compose up -d --build -V; \
		echo "$(CURRENT_DEPS_HASH)" > $(DEPS_HASH_FILE); \
	else \
		docker compose up -d; \
	fi
```

The `-V` flag recreates anonymous volumes, ensuring fresh `node_modules` or `.venv` directories inside containers.

## Templates

### Makefile Template

```makefile
# === Port Allocation ===
# CUSTOMIZE: Add/remove port checks for your services
_PORT_OFFSET := $(shell \
	pref=$$(( $$(printf '%s' "$(CURDIR)" | cksum | cut -d' ' -f1 | head -c4) % 100 )); \
	used=$$(ss -tln 2>/dev/null); \
	for i in $$(seq 0 99); do \
		o=$$(( (pref + i) % 100 )); \
		fp=$$(( 3000 + o )); ap=$$(( 8000 + o )); \
		if ! echo "$$used" | grep -qE ":$$fp\s" \
		&& ! echo "$$used" | grep -qE ":$$ap\s"; then \
			echo $$o; exit 0; \
		fi; \
	done; \
	echo $$pref)

# CUSTOMIZE: One export per service port
export FRONTEND_PORT := $(shell echo $$(( 3000 + $(_PORT_OFFSET) )))
export API_PORT      := $(shell echo $$(( 8000 + $(_PORT_OFFSET) )))

# === Project Naming ===
PARENT_DIR := $(notdir $(patsubst %/,%,$(dir $(CURDIR))))
export COMPOSE_PROJECT_NAME := $(PARENT_DIR)-$(notdir $(CURDIR))

# === Hostname Generation ===
SERVER_IP := $(shell grep -q microsoft /proc/version 2>/dev/null \
	&& echo 127.0.0.1 \
	|| ip route get 1.1.1.1 2>/dev/null | awk '{print $$7; exit}')

# CUSTOMIZE: One hostname per service
export FRONTEND_HOST := $(COMPOSE_PROJECT_NAME)-frontend.$(SERVER_IP).nip.io
export API_HOST      := $(COMPOSE_PROJECT_NAME)-api.$(SERVER_IP).nip.io

# === Shared Network ===
# CUSTOMIZE: Network name shared across all worktrees
SHARED_NETWORK_NAME := my-project-shared
export SHARED_NETWORK_NAME

# === Dependency Hash ===
DEPS_HASH_FILE := .deps-hash
# CUSTOMIZE: Your dependency/lock files
DEPS_FILES := front/package.json api/pyproject.toml $(wildcard front/bun.lock api/uv.lock)
CURRENT_DEPS_HASH := $(shell cat $(DEPS_FILES) 2>/dev/null | md5sum | cut -d' ' -f1)
STORED_DEPS_HASH  := $(shell cat $(DEPS_HASH_FILE) 2>/dev/null)

# === Targets ===

.PHONY: dev down status infra

infra:
	@docker network inspect $(SHARED_NETWORK_NAME) >/dev/null 2>&1 \
		|| docker network create $(SHARED_NETWORK_NAME)
	docker compose -f docker-compose.infra.yml up -d

dev: infra
	@if [ "$(CURRENT_DEPS_HASH)" != "$(STORED_DEPS_HASH)" ]; then \
		echo "Dependencies changed, rebuilding with -V..."; \
		docker compose up -d --build -V; \
		echo "$(CURRENT_DEPS_HASH)" > $(DEPS_HASH_FILE); \
	else \
		docker compose up -d; \
	fi
	@# Generate nginx vhost
	@printf 'server {\n\tlisten 80;\n\tserver_name $(FRONTEND_HOST);\n\tlocation / {\n\t\tproxy_pass http://127.0.0.1:$(FRONTEND_PORT);\n\t\tproxy_http_version 1.1;\n\t\tproxy_set_header Host $$host;\n\t\tproxy_set_header Upgrade $$http_upgrade;\n\t\tproxy_set_header Connection "upgrade";\n\t}\n}\nserver {\n\tlisten 80;\n\tserver_name $(API_HOST);\n\tlocation / {\n\t\tproxy_pass http://127.0.0.1:$(API_PORT);\n\t\tproxy_http_version 1.1;\n\t\tproxy_set_header Host $$host;\n\t\tproxy_set_header Upgrade $$http_upgrade;\n\t\tproxy_set_header Connection "upgrade";\n\t}\n}\n' \
		| sudo tee /etc/nginx/sites-enabled/$(COMPOSE_PROJECT_NAME) > /dev/null
	@sudo nginx -t && sudo nginx -s reload
	@echo ""
	@echo "Frontend: http://$(FRONTEND_HOST)"
	@echo "API:      http://$(API_HOST)"
	@echo ""

down:
	docker compose down
	@sudo rm -f /etc/nginx/sites-enabled/$(COMPOSE_PROJECT_NAME)
	@sudo nginx -t 2>/dev/null && sudo nginx -s reload

status:
	@echo "Project: $(COMPOSE_PROJECT_NAME)"
	@echo "Frontend: http://$(FRONTEND_HOST) (port $(FRONTEND_PORT))"
	@echo "API:      http://$(API_HOST) (port $(API_PORT))"
	@docker compose ps
```

### docker-compose.yml Template

```yaml
# CUSTOMIZE: Define your application services
services:
  frontend:
    build:
      context: ./front
      target: development  # CUSTOMIZE: Dockerfile target
    ports:
      - "${FRONTEND_PORT:-3000}:3000"  # CUSTOMIZE: internal port
    environment:
      - API_URL=http://${API_HOST}  # CUSTOMIZE: env vars for your framework
    volumes:
      - ./front:/app  # CUSTOMIZE: source mount path
    networks:
      - ${SHARED_NETWORK_NAME}
    extra_hosts:
      - "host.docker.internal:host-gateway"

  api:
    build:
      context: ./api
      target: development  # CUSTOMIZE: Dockerfile target
    ports:
      - "${API_PORT:-8000}:8000"  # CUSTOMIZE: internal port
    environment:
      - DATABASE_URL=postgresql://user:pass@db:5432/mydb  # CUSTOMIZE
      - CORS_ORIGINS=http://${FRONTEND_HOST:-localhost:3000}  # CUSTOMIZE
    volumes:
      - ./api:/app  # CUSTOMIZE: source mount path
    networks:
      - ${SHARED_NETWORK_NAME}
    extra_hosts:
      - "host.docker.internal:host-gateway"

networks:
  ${SHARED_NETWORK_NAME}:
    external: true
```

### docker-compose.infra.yml Template

```yaml
# Shared infrastructure — run ONCE, used by ALL worktrees
# CUSTOMIZE: Add your database and cache services
services:
  db:
    image: postgres:16-alpine  # CUSTOMIZE: database image
    environment:
      POSTGRES_USER: user      # CUSTOMIZE
      POSTGRES_PASSWORD: pass   # CUSTOMIZE
      POSTGRES_DB: mydb         # CUSTOMIZE
    volumes:
      - db-data:/var/lib/postgresql/data  # CUSTOMIZE: data path
    ports:
      - "5432:5432"  # CUSTOMIZE: expose if needed for local tools
    networks:
      - ${SHARED_NETWORK_NAME:-my-project-shared}

  cache:
    image: redis:7-alpine  # CUSTOMIZE: cache image
    ports:
      - "6379:6379"  # CUSTOMIZE
    networks:
      - ${SHARED_NETWORK_NAME:-my-project-shared}

volumes:
  db-data:

networks:
  ${SHARED_NETWORK_NAME:-my-project-shared}:
    name: ${SHARED_NETWORK_NAME:-my-project-shared}
    driver: bridge
```

### nginx Vhost Template

```nginx
# CUSTOMIZE: One server block per service per worktree
server {
    listen 80;
    server_name ${SERVICE_HOST};  # CUSTOMIZE: nip.io hostname

    location / {
        proxy_pass http://127.0.0.1:${SERVICE_PORT};  # CUSTOMIZE: mapped port
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

## Language-Specific Variations

### Python Variation: Stale .venv Guard

When bind-mounting a Python project into a container, the `.venv` directory may contain broken symlinks from a different Python version or architecture. Detect and clean:

```bash
# In docker-entrypoint.sh
if [ -L ".venv/bin/python3" ] && [ ! -x ".venv/bin/python3" ]; then
    echo "Stale .venv detected (broken symlink), recreating..."
    rm -rf .venv
    uv sync
fi
```

### Python Variation: Worker Hot-Reload

Use `watchfiles` for development hot-reload with a `SERVICE_MODE` conditional:

```bash
# In docker-entrypoint.sh
if [ "$SERVICE_MODE" = "worker" ]; then
    if [ "$APP_ENV" = "development" ]; then
        exec watchfiles "python -m app.workers" app/
    else
        exec python -m app.workers
    fi
fi
```

### Node.js Variation: Vite Dev Server

Vite requires explicit allowed hosts when accessed via non-localhost hostnames:

```yaml
# In docker-compose.yml, frontend service environment
environment:
  - VITE_ALLOWED_HOST=${FRONTEND_HOST:-}
```

### Node.js Variation: Worker Hot-Reload

Use `nodemon` or `tsx --watch` for development:

```bash
if [ "$NODE_ENV" = "development" ]; then
    exec npx nodemon --watch src/ --ext ts,js src/worker.ts
else
    exec node dist/worker.js
fi
```

## Full Lifecycle

### Creating and Running a Worktree

```bash
# 1. Create worktree for a feature branch
git worktree add ../my-project-feature-auth feature/auth

# 2. Enter the worktree
cd ../my-project-feature-auth

# 3. Start shared infrastructure (only needed once across all worktrees)
make infra

# 4. Start the dev environment
make dev
# Output:
#   Frontend: http://my-project-feature-auth-frontend.192.168.1.50.nip.io
#   API:      http://my-project-feature-auth-api.192.168.1.50.nip.io

# 5. Check status
make status

# 6. Stop the environment
make down

# 7. Clean up worktree when done
cd ../my-project
git worktree remove ../my-project-feature-auth
```

### Garbage Collection (Orphaned Containers)

```bash
# Find containers from removed worktrees
docker ps -a --filter "label=com.docker.compose.project" --format "{{.Labels}}" | \
    grep -oP 'com.docker.compose.project=\K[^,]+' | sort -u

# Remove orphaned project containers
docker compose -p <orphaned-project-name> down -v
```

## Examples

### Example 1: Python/FastAPI + PostgreSQL

Two worktrees running simultaneously — `main` on ports 3042/8042 and `feature/payments` on ports 3067/8067. Shared PostgreSQL via `docker-compose.infra.yml`. API calls between services use nip.io hostnames with loopback fallback. Nginx routes both sets of hostnames.

### Example 2: Node.js + Redis + RabbitMQ

Frontend (Vite + React), API (Express), Worker (Bull queue processor). Redis shared via infra compose. RabbitMQ isolated per worktree (ports 5672+offset, 15672+offset). Worker hot-reloads via `nodemon` in development. `VITE_ALLOWED_HOST` set for each worktree's frontend hostname.

### Example 3: Creating a Second Worktree

Developer already has `main` running. Creates `git worktree add ../project-hotfix hotfix/urgent`. Runs `make dev` in the new worktree. Port hashing produces a different offset (different `CURDIR`). Collision detection confirms ports are free. Nginx gets a second vhost. Both branches now accessible via separate nip.io hostnames simultaneously.

## Troubleshooting

### Port Collision

**Symptom**: `make dev` starts but a service fails to bind its port.
**Cause**: Another process (not tracked by `ss -tln` at Makefile evaluation time) grabbed the port.
**Fix**: Run `make down && make dev` to re-evaluate ports. If persistent, check for non-Docker processes on the port range with `ss -tlnp | grep <port>`.

### nip.io Not Resolving Inside Container

**Symptom**: Container HTTP client gets DNS resolution failure or connects to wrong service.
**Cause**: Missing `extra_hosts` directive; `host.docker.internal` not defined.
**Fix**: Add `extra_hosts: ["host.docker.internal:host-gateway"]` to the service in `docker-compose.yml`. Ensure the loopback fallback function is implemented in your HTTP client code.

### nginx Not Routing

**Symptom**: Browser shows "502 Bad Gateway" or nginx default page.
**Cause**: Vhost not generated, nginx not reloaded, or service not yet listening.
**Fix**: Verify vhost exists: `cat /etc/nginx/sites-enabled/<project-name>`. Test config: `sudo nginx -t`. Reload: `sudo nginx -s reload`. Check service is up: `docker compose ps`.

### Migration Conflicts Between Worktrees

**Symptom**: Database migration fails because another worktree applied a conflicting migration.
**Cause**: Shared database means all worktrees' migrations apply to the same schema.
**Fix**: Coordinate migration ordering across branches. For heavy schema changes, consider temporary per-worktree database isolation. Run migrations from only one worktree at a time.

### Stale Containers After Worktree Removal

**Symptom**: `docker ps` shows containers from a branch that no longer exists.
**Cause**: `make down` was not run before `git worktree remove`.
**Fix**: `docker compose -p <old-project-name> down -v` to clean up. Add a pre-removal check to your workflow: always `make down` before removing a worktree.

## Caveats and Known Limitations

- **nip.io and corporate DNS**: Some corporate DNS servers block or intercept wildcard DNS services like nip.io. Workaround: use manual `/etc/hosts` entries or a local DNS resolver (e.g., dnsmasq).
- **extra_hosts Linux-only requirement**: `host.docker.internal:host-gateway` must be explicitly declared on Linux. Docker Desktop on macOS/Windows handles this automatically.
- **Port range saturation**: With 100 offsets and multiple services per worktree, running more than ~20 simultaneous worktrees risks exhausting the offset space. Increase the modulo (e.g., `% 200`) if needed.
- **Docker network limit**: Docker has a default limit of ~30 networks. Shared infrastructure mitigates this, but many worktrees with per-worktree networks can hit the limit.
- **TOCTOU race in port allocation**: The `ss -tln` check happens at Makefile evaluation time. A port can be claimed between evaluation and Docker container startup. This is rare in practice and resolved by re-running `make dev`.
- **Migration conflicts**: Shared databases mean migration ordering matters across worktrees. Teams should coordinate schema changes or use feature flags instead of schema-breaking migrations.

## References

Patterns in this document were derived from three production implementations: a video editor platform, a real-time chat application, and an e-commerce editor. These are credited here for provenance but are NOT required — all patterns above are fully self-contained and project-agnostic.
