# Troubleshooting

## Contents

- Each worktree spun up its own database
- Worktree A talks to worktree B's broker/cache
- Infra dead after host reboot / `make dev` hangs
- `make dev` fails after a service rename
- 413 on uploads
- HMR not reloading
- OAuth redirect goes to localhost
- nip.io not resolving inside a container
- Cross-stack token/issuer validation fails
- nginx 502 / default page
- Disk filling with anonymous volumes
- nip.io blocked by corporate DNS
- Migration conflicts between worktrees
- Stale containers after worktree removal

---

**Each worktree spun up its own database.**
Cause: infra brought up without the pinned `-p <slug>-infra` (so
`COMPOSE_PROJECT_NAME` namespaced it per worktree). Fix: always `make infra`
(which sets `-p`); never `docker compose -f docker-compose.infra.yml up` bare.
Verify one container: `docker ps | grep shared`.

**Worktree A talks to worktree B's broker/cache.**
Cause: per-worktree services placed on the shared network, so service-name DNS
collides. Fix: put broker/cache on the private `internal` network (see
reference/networking.md).

**Infra dead after host reboot / `make dev` hangs at "waiting for...".**
Cause: missing `restart: unless-stopped`; the readiness loop polls a dead
container forever and `up -d` won't recreate it (container_name conflict). Fix:
add the restart policy to every infra service; recover now with
`docker rm <dead-container> && make infra`.

**`make dev` fails / orphan containers after a service rename.**
Cause: renamed compose services leave stale containers that block `up`. Fix:
`make down` uses `--remove-orphans`; if needed run
`docker compose down --remove-orphans` once.

**413 (Request Entity Too Large) on uploads.**
Cause: nginx default `client_max_body_size` is 1m. Fix: the generated vhost sets
it higher; raise it in the Makefile's vhost printf if your uploads are larger.

**File edits don't hot-reload (HMR silent).**
Cause: inotify doesn't cross host→container bind mounts on Linux. Fix: set
`VITE_USE_POLLING=true` (default) and ensure `vite.config.ts` reads
`watch.usePolling` (see templates/vite.config.snippet.ts).

**OAuth/social login redirects to `localhost:8000` instead of the nip.io host.**
Cause: callback URLs are built from a base-URL config that defaults to
localhost. Fix: pass `APP_URL=http://${API_HOST}` to the api service — single
`$`, not `$$` (a double `$$` passes the literal string un-substituted and is
itself the bug).

**nip.io URL fails or hits the wrong service from inside a container.**
Cause: nip.io resolves to a loopback IP = the container itself; and/or missing
`extra_hosts`. Fix: add `extra_hosts: ["host.docker.internal:host-gateway"]` and
route outbound calls through `scripts/resolve_loopback_url.py`.

**Cross-stack id_token / discovery / JWKS validation fails.**
Cause: an issuer or shared URL differs between the two stacks. Fix: make it
identical byte-for-byte on both sides; reach the other stack via
`host.docker.internal:<published-port>`, not localhost/service name.

**Browser shows 502 Bad Gateway or the nginx default page.**
Cause: vhost missing, nginx not reloaded, or the service isn't listening yet.
Fix: `cat /etc/nginx/sites-enabled/<project>`, `nginx -t`, `nginx -s reload`,
`docker compose ps`.

**Disk filling with anonymous volumes.**
Cause: every `-V` rebuild orphans the prior anon node_modules/.venv volume. Fix:
`make down` reclaims them; bulk clean with `docker volume prune` (careful).

**nip.io won't resolve at all.**
Cause: corporate DNS blocks wildcard DNS services. Fix: `/etc/hosts` entries or
a local resolver (dnsmasq). `scripts/check_host_deps.sh` flags this.

**Migration fails because another worktree applied a conflicting migration.**
Cause: shared DB means all branches share one schema. Fix: coordinate migration
order, run migrations from one worktree at a time, or temporarily isolate the DB
per worktree for heavy schema work.

**`docker ps` shows containers from a removed worktree.**
Cause: `make down` wasn't run before `git worktree remove`. Fix:
`docker compose -p <old-project-name> down -v`. Always `make down` first.

## Garbage-collecting orphaned project containers

```bash
docker ps -a --filter "label=com.docker.compose.project" \
  --format '{{.Label "com.docker.compose.project"}}' | sort -u
docker compose -p <orphaned-project-name> down -v
```
