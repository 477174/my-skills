# Networking: topology, hostnames, and the loopback fallback

## Contents

- Two-network topology (and why one network is wrong)
- nip.io hostname pattern
- nip.io loopback fallback (container-to-container)
- Cross-stack communication (separate compose stacks)
- nginx reverse proxy

## Two-network topology

Use exactly two networks. Putting every service on one shared network is the
most common silent isolation bug in multi-worktree setups.

| Network | Scope | Members | Why |
|---------|-------|---------|-----|
| `shared` | external, all worktrees + infra | app server, workers, anything reaching the shared DB or `host.docker.internal` | one bridge for cross-stack + infra reach |
| `internal` | private, per worktree | broker, cache (if per-worktree) | keeps service-name DNS unambiguous |

**The collision:** each worktree's compose defines a service literally named
`broker` (or `redis`, `db`, ...). On a single shared network they all claim the
same network alias, so an API in worktree A can resolve `broker` to worktree
B's container — cross-branch queue/cache contamination that looks like flaky
data. Isolating per-worktree services on a private `internal` network makes
their names resolve only within their own stack.

Confirm isolation at runtime — each worktree should have its own `*_internal`
network and there should be exactly one shared infra container:

```bash
docker network ls | grep -E 'shared|internal'
docker ps --format '{{.Names}}' | grep -E 'broker|cache' | sort
```

## nip.io hostname pattern

`nip.io` is wildcard DNS: `anything.<ip>.nip.io` resolves to `<ip>`. This gives
predictable, per-worktree, per-service hostnames with zero `/etc/hosts` edits.

The Makefile derives them as:

```
<COMPOSE_PROJECT_NAME>-<service>.<SERVER_IP>.nip.io
```

A worktree at `/code/my-project/feature-auth` →
`my-project-feature-auth-api.127.0.0.1.nip.io`. On WSL use `127.0.0.1`
(WSL resolves its own routed IP poorly); on native Linux use the route IP so
other machines on the LAN can reach it.

## nip.io loopback fallback (CRITICAL)

Inside a container, a loopback IP (e.g. `127.0.0.1` that nip.io returns) means
the container itself — not the host. So any container-to-container or
container-to-host HTTP call through a nip.io URL fails or hits the wrong
service. Detect a loopback resolution and rewrite the host to
`host.docker.internal`, preserving the original `Host` header for vhost routing.

Use the bundled `scripts/resolve_loopback_url.py` (import `resolve_loopback_url`,
or run it directly to test a URL). Algorithm:

```
hostname = parse(url).host
if dns_resolve(hostname).is_loopback:
    url  = replace_host(url, "host.docker.internal")
    host_header = hostname           # keep for the Host header
```

**Requirement:** every service that makes such outbound calls needs
`extra_hosts: ["host.docker.internal:host-gateway"]`. This is automatic on
Docker Desktop (macOS/Windows) but **must be explicit on Linux** or
`host.docker.internal` won't resolve.

## Cross-stack communication (separate compose stacks)

When a second, independent compose stack must be reached (e.g. a CRM running as
its own stack, or another worktree), do **not** use the service name or
`localhost`. Reach it via the host gateway plus its published port:

```
OTHER_API_URL=http://host.docker.internal:8003
```

**SSoT rule:** any value that must match across both stacks — an OAuth/OIDC
issuer, a shared callback base URL, a signing audience — must be **identical
byte-for-byte on both sides**, or token/discovery validation fails. Set it once
and inject the same string into both stacks. For browser-facing SSO redirects,
prefer the nip.io host (resolvable everywhere) over `host.docker.internal`
(only resolvable inside containers).

## nginx reverse proxy

The host nginx routes each nip.io hostname to the worktree's mapped host port.
`make dev` writes one vhost per browser-facing service to
`/etc/nginx/sites-enabled/<project>` and reloads. See
`templates/nginx-vhost.conf` for the annotated block. Essentials:

- `client_max_body_size` > default 1m, or uploads 413.
- `Upgrade`/`Connection "upgrade"` headers, or WebSocket/HMR breaks.
- long `proxy_read_timeout` + `proxy_buffering off` for SSE/streaming endpoints.

Host prerequisites: nginx installed, `/etc/nginx/sites-enabled` exists and is
`include`d from `nginx.conf`'s `http{}` block, and the user running `make` can
write to it (run as root, or via sudo). `scripts/check_host_deps.sh` verifies all
of this.
