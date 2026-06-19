#!/usr/bin/env bash
# Preflight for the multi-worktree dev setup. Run before the first `make dev`.
# Reports missing host prerequisites instead of letting `make dev` fail opaquely.
set -u

ok=true
note() { printf '  %s\n' "$1"; }
pass() { printf '\033[32mOK\033[0m   %s\n' "$1"; }
fail() { printf '\033[31mMISS\033[0m %s\n' "$1"; ok=false; }

echo "== host dependencies =="
command -v docker >/dev/null 2>&1 && pass "docker" || fail "docker not found"
docker compose version >/dev/null 2>&1 && pass "docker compose v2" \
  || fail "docker compose v2 plugin not found"
command -v nginx >/dev/null 2>&1 && pass "nginx" \
  || fail "nginx not found (host reverse proxy)"
command -v ss >/dev/null 2>&1 && pass "ss (iproute2)" \
  || fail "ss not found — port collision detection needs it (or adapt to lsof)"
command -v make >/dev/null 2>&1 && pass "make" || fail "make not found"

echo "== nginx wiring =="
if [ -d /etc/nginx/sites-enabled ]; then
  pass "/etc/nginx/sites-enabled exists"
  if [ -w /etc/nginx/sites-enabled ]; then
    pass "sites-enabled is writable by $(id -un)"
  else
    fail "sites-enabled not writable — run make as root or via sudo"
  fi
  if nginx -T 2>/dev/null | grep -q 'sites-enabled'; then
    pass "sites-enabled is included by nginx.conf"
  else
    note "warn: could not confirm 'include .../sites-enabled/*' in nginx.conf"
  fi
else
  fail "/etc/nginx/sites-enabled missing — create it and include it in nginx.conf"
fi

echo "== nip.io resolution =="
if command -v getent >/dev/null 2>&1; then
  if getent hosts test.127.0.0.1.nip.io >/dev/null 2>&1; then
    pass "nip.io resolves (test.127.0.0.1.nip.io)"
  else
    fail "nip.io not resolving — corporate DNS may block it; use /etc/hosts or dnsmasq"
  fi
fi

echo
if $ok; then
  echo "All required checks passed."; exit 0
else
  echo "Fix the MISS items above before running make dev."; exit 1
fi
