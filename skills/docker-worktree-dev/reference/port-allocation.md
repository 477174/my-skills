# Port allocation

## How it works

The Makefile hashes the worktree's absolute path to a deterministic offset, then
linear-probes to skip ports already bound:

1. `cksum` of `$(CURDIR)` → number; `% 100` → preferred offset `0..99`. The same
   directory always prefers the same offset, so a worktree keeps stable ports
   across restarts.
2. `ss -tln` captures currently-listening TCP ports.
3. If `base+offset` is taken for any service, try `(pref+1)%100`, `(pref+2)%100`,
   … up to 100 probes, then fall back to the original preference.

Base ranges and the per-service exports must stay in sync: every base checked in
the probe loop (`fp`, `ap`, `mp`, …) needs a matching `export <SERVICE>_PORT`.
Recommended bases: `3000` frontend, `8000` API, `15672` broker mgmt UI; add more
as needed (e.g. `5672` AMQP, `5173` a second frontend).

## Adding a service port

In the probe loop add the base and a `grep -qE` guard, then export it:

```makefile
# inside the if-test, add a new base:
xp=$$(( 9000 + o )); \
# ... && ! echo "$$used" | grep -qE ":$$xp\s"; then
export EXTRA_PORT := $(shell echo $$(( 9000 + $(_PORT_OFFSET) )))
```

## Tradeoffs and limits

- **TOCTOU race:** the `ss` check runs at Makefile evaluation time; a port can be
  claimed between evaluation and container start. Rare; `make down && make dev`
  re-evaluates.
- **Offset saturation:** 100 offsets × several services/worktree means ~20+
  simultaneous worktrees can exhaust the space. Widen the modulo (`% 200`) and
  the base spacing if you run more.
- **Non-Docker port holders:** a process `ss` didn't see at eval time can still
  collide. Find it with `ss -tlnp | grep <port>`.
- **macOS:** `ss` is Linux-only; swap the probe to `lsof -iTCP -sTCP:LISTEN`.

## Only expose what you need, bound to loopback

Publish a host port only for services a human/tool reaches directly (frontend,
API, a broker management UI), and bind non-public ones to loopback:
`127.0.0.1:${BROKER_MGMT_PORT}:15672`. Keep AMQP (5672), the DB, and the cache
on the Docker network with no host port — avoids clashes with other local
instances and shrinks attack surface.
