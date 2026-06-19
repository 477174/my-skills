# ==============================================================================
# Multi-Worktree Development Makefile
# ==============================================================================
# Usage:
#   make infra    # Start shared infrastructure (DB/cache) once — pinned project
#   make dev      # Start this worktree's services (auto port + nip.io + nginx)
#   make down     # Stop services, reclaim anon volumes, remove nginx vhost
#   make ps       # Show running containers (this worktree + infra)
#   make ports    # Print allocated ports/hosts (machine-readable)
# ==============================================================================
# CUSTOMIZE markers show where to adapt per project. Everything else is a fix
# learned in production — change it only if you understand the consequence.
# ==============================================================================

# === Project Naming (sanitized) ==============================================
# COMPOSE_PROJECT_NAME must be lowercase alnum + hyphen/underscore and start
# with alnum. Worktrees can live under paths with uppercase (e.g. ~/Projects),
# so sanitize: lowercase, map invalid chars -> '-', strip leading non-alnum.
PARENT_DIR := $(notdir $(patsubst %/,%,$(dir $(CURDIR))))
_RAW_PROJECT_NAME := $(PARENT_DIR)-$(notdir $(CURDIR))
export COMPOSE_PROJECT_NAME := $(shell printf '%s' "$(_RAW_PROJECT_NAME)" \
	| tr '[:upper:]' '[:lower:]' \
	| sed 's/[^a-z0-9_-]/-/g; s/^[^a-z0-9]*//')

# === Shared Infra Identity ===================================================
# CUSTOMIZE: project slug used for the shared network + pinned infra project.
PROJECT_SLUG := my-project
SHARED_NETWORK_NAME := $(PROJECT_SLUG)-shared
export SHARED_NETWORK_NAME
# Pin infra to a STABLE project name so it is shared across ALL worktrees.
# Without -p, COMPOSE_PROJECT_NAME would namespace infra per worktree and each
# branch would get its own database — defeating shared infrastructure.
INFRA_COMPOSE := docker compose -f docker-compose.infra.yml -p $(PROJECT_SLUG)-infra
# CUSTOMIZE: container name of the readiness-gated infra service (see infra:).
INFRA_READY_CONTAINER := $(PROJECT_SLUG)-shared-db

# === Port Allocation (deterministic hash + collision probing) ================
# Hash CURDIR -> preferred offset 0..99, then linear-probe to skip ports
# already bound (per ss -tln). Same directory always prefers the same offset.
# CUSTOMIZE: add/remove the per-service port checks (fp/ap/...) to match below.
_PORT_OFFSET := $(shell \
	pref=$$(( $$(printf '%s' "$(CURDIR)" | cksum | cut -d' ' -f1 | head -c4) % 100 )); \
	used=$$(ss -tln 2>/dev/null); \
	for i in $$(seq 0 99); do \
		o=$$(( (pref + i) % 100 )); \
		fp=$$(( 3000 + o )); ap=$$(( 8000 + o )); mp=$$(( 15672 + o )); \
		if ! echo "$$used" | grep -qE ":$$fp\s" \
		&& ! echo "$$used" | grep -qE ":$$ap\s" \
		&& ! echo "$$used" | grep -qE ":$$mp\s"; then \
			echo $$o; exit 0; \
		fi; \
	done; \
	echo $$pref)

# CUSTOMIZE: one export per service port (base + offset).
export FRONTEND_PORT      := $(shell echo $$(( 3000 + $(_PORT_OFFSET) )))
export API_PORT           := $(shell echo $$(( 8000 + $(_PORT_OFFSET) )))
export BROKER_MGMT_PORT   := $(shell echo $$(( 15672 + $(_PORT_OFFSET) )))

# === Hostname Generation =====================================================
# WSL resolves its own IP poorly; use 127.0.0.1 there. Native Linux: route IP.
SERVER_IP := $(shell grep -q microsoft /proc/version 2>/dev/null \
	&& echo 127.0.0.1 \
	|| ip route get 1.1.1.1 2>/dev/null | awk '{print $$7; exit}')

# CUSTOMIZE: one hostname per browser-facing service.
export FRONTEND_HOST := $(COMPOSE_PROJECT_NAME)-frontend.$(SERVER_IP).nip.io
export API_HOST      := $(COMPOSE_PROJECT_NAME)-api.$(SERVER_IP).nip.io

# === Frontend env (consumed by vite.config.ts) ===============================
# CUSTOMIZE for your framework. These wire dynamic hosts/ports into the dev
# server (allowed hosts, API proxy target, HMR polling). See vite snippet.
export VITE_ALLOWED_HOST     := $(FRONTEND_HOST)
export VITE_API_BASE_URL     := http://$(API_HOST)
export VITE_API_PROXY_TARGET := http://api:8000
export VITE_USE_POLLING      := true

# === API env =================================================================
# CUSTOMIZE: CORS origin(s) the API must accept from the browser.
export ALLOWED_ORIGINS := http://$(FRONTEND_HOST)

# === Dependency Hash Auto-Rebuild ============================================
# Rebuild containers (with -V to refresh anon node_modules/.venv) only when a
# tracked dependency/lock file changes. Avoids a full rebuild every `make dev`.
DEPS_HASH_FILE := .deps-hash
# CUSTOMIZE: list your dependency/lock files.
DEPS_FILES := front/package.json api/pyproject.toml \
	$(wildcard front/bun.lock front/package-lock.json api/uv.lock api/poetry.lock)
CURRENT_DEPS_HASH := $(shell cat $(DEPS_FILES) 2>/dev/null | md5sum | cut -d' ' -f1)
STORED_DEPS_HASH  := $(shell cat $(DEPS_HASH_FILE) 2>/dev/null)

# === nginx vhost path ========================================================
NGINX_CONF := /etc/nginx/sites-enabled/$(COMPOSE_PROJECT_NAME)

.PHONY: dev down ps ports infra infra-down

# Shared infra: create the external network, then bring infra up under the
# PINNED project name and BLOCK until the readiness-gated service answers.
# Idempotent: skips startup if the container is already running.
infra:
	@docker network inspect $(SHARED_NETWORK_NAME) >/dev/null 2>&1 \
		|| docker network create $(SHARED_NETWORK_NAME)
	@if docker ps -q -f name=$(INFRA_READY_CONTAINER) | grep -q .; then \
		echo "[infra] $(INFRA_READY_CONTAINER) already running"; \
	else \
		$(INFRA_COMPOSE) up -d; \
		echo "[infra] waiting for $(INFRA_READY_CONTAINER)..."; \
		until docker exec $(INFRA_READY_CONTAINER) true >/dev/null 2>&1 \
			&& $(INFRA_COMPOSE) ps --status running | grep -q $(INFRA_READY_CONTAINER); do \
			sleep 2; done; \
		echo "[infra] ready"; \
	fi
	@# CUSTOMIZE: replace the `docker exec ... true` probe above with a real
	@# readiness check, e.g. `cqlsh -e 'SELECT now() FROM system.local'`,
	@# `pg_isready`, or `redis-cli ping`, so dev never races a cold database.

dev: infra
	@if [ "$(CURRENT_DEPS_HASH)" != "$(STORED_DEPS_HASH)" ]; then \
		echo "[deps] changed — rebuilding with -V (fresh anon volumes)..."; \
		docker compose up -d --build -V; \
		echo "$(CURRENT_DEPS_HASH)" > $(DEPS_HASH_FILE); \
	else \
		docker compose up -d; \
	fi
	@# Generate one nginx vhost per browser-facing service. client_max_body_size
	@# lets file uploads through; the Upgrade/Connection headers carry WebSocket
	@# (HMR) traffic. CUSTOMIZE: add a server block per extra host.
	@printf 'server {\n\tlisten 80;\n\tserver_name $(FRONTEND_HOST);\n\tclient_max_body_size 25m;\n\tlocation / {\n\t\tproxy_pass http://127.0.0.1:$(FRONTEND_PORT);\n\t\tproxy_http_version 1.1;\n\t\tproxy_set_header Host $$host;\n\t\tproxy_set_header Upgrade $$http_upgrade;\n\t\tproxy_set_header Connection "upgrade";\n\t}\n}\nserver {\n\tlisten 80;\n\tserver_name $(API_HOST);\n\tclient_max_body_size 25m;\n\tlocation / {\n\t\tproxy_pass http://127.0.0.1:$(API_PORT);\n\t\tproxy_http_version 1.1;\n\t\tproxy_set_header Host $$host;\n\t\tproxy_set_header Upgrade $$http_upgrade;\n\t\tproxy_set_header Connection "upgrade";\n\t\tproxy_read_timeout 3600s;\n\t\tproxy_send_timeout 3600s;\n\t}\n}\n' > $(NGINX_CONF)
	@nginx -t >/dev/null 2>&1 && nginx -s reload 2>/dev/null || true
	@# .dev-urls: consumed by AI tools so they never guess localhost:PORT.
	@printf '# Auto-generated by make dev — do not edit\nFRONTEND_URL=http://$(FRONTEND_HOST)\nAPI_URL=http://$(API_HOST)\nAPI_DOCS=http://$(API_HOST)/docs\n' > .dev-urls
	@echo ""
	@echo "[$(COMPOSE_PROJECT_NAME)]"
	@echo "  Frontend -> http://$(FRONTEND_HOST)"
	@echo "  API      -> http://$(API_HOST)"
	@echo "  Broker   -> http://127.0.0.1:$(BROKER_MGMT_PORT)"
	@echo "  ports: frontend :$(FRONTEND_PORT)  api :$(API_PORT)  broker-mgmt :$(BROKER_MGMT_PORT)"
	@echo ""

# Reclaim the anonymous node_modules/.venv volumes that `-V` orphans, or they
# accumulate (gigabytes across many worktrees). Then drop the nginx vhost.
down:
	@anon=$$(docker compose ps -aq 2>/dev/null \
	  | xargs -r docker inspect -f '{{range .Mounts}}{{if .Name}}{{println .Name}}{{end}}{{end}}' 2>/dev/null \
	  | grep -E '^[0-9a-f]{64}$$' | sort -u); \
	docker compose down --remove-orphans; \
	if [ -n "$$anon" ]; then echo "$$anon" | xargs -r docker volume rm 2>/dev/null || true; \
	  echo "[$(COMPOSE_PROJECT_NAME)] reclaimed anonymous node_modules/.venv volumes"; fi
	@rm -f .dev-urls
	@rm -f $(NGINX_CONF)
	@nginx -t >/dev/null 2>&1 && nginx -s reload 2>/dev/null || true
	@echo "[$(COMPOSE_PROJECT_NAME)] removed nginx vhost"

infra-down:
	$(INFRA_COMPOSE) down

ps:
	docker compose ps
	@echo ""
	$(INFRA_COMPOSE) ps

ports:
	@echo "COMPOSE_PROJECT_NAME=$(COMPOSE_PROJECT_NAME)"
	@echo "FRONTEND_HOST=$(FRONTEND_HOST)"
	@echo "API_HOST=$(API_HOST)"
	@echo "FRONTEND_PORT=$(FRONTEND_PORT)"
	@echo "API_PORT=$(API_PORT)"
	@echo "BROKER_MGMT_PORT=$(BROKER_MGMT_PORT)"
