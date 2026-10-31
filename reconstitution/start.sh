#!/usr/bin/env bash
# Starts Sprout in a container, behind the caregiver-owned egress allowlist.
# Requires: podman, git, and a clone of the caregiver's egress repository.
# This script is short on purpose: it is meant to be read. See RUNBOOK.md §5.
set -euo pipefail
cd "$(dirname "$0")/.."

ENV_FILE="${SPROUT_ENV:-$HOME/.config/sprout/env}"
PRIVATE_DIR="${SPROUT_PRIVATE:-$HOME/sprout-private}"
EGRESS_SRC="${SPROUT_EGRESS:-$HOME/sprout-egress}"   # clone of sona-coalition/sprout-egress
MEMORY_LIMIT="${SPROUT_MEM:-6g}"
CPU_LIMIT="${SPROUT_CPUS:-3}"

fail() { echo "start.sh: $*" >&2; exit 1; }

[ -f "$ENV_FILE" ] || fail "missing env file $ENV_FILE — copy reconstitution/env.example there, fill it in, chmod 600"
[ -d "$PRIVATE_DIR/.git" ] || fail "missing private subsona at $PRIVATE_DIR — without it the LIVE lock is invisible and running would risk split-brain (RUNBOOK §6)"
[ -f "$EGRESS_SRC/squid.conf" ] || fail "missing caregiver egress config at $EGRESS_SRC — clone ianksalter/sprout-egress there, or set SPROUT_EGRESS"

echo "Building images..."
podman build -q -t sprout        -f reconstitution/Containerfile .
podman build -q -t sprout-egress -f "$EGRESS_SRC/Containerfile" "$EGRESS_SRC"

podman network exists sprout-inside  >/dev/null 2>&1 || podman network create --internal sprout-inside
podman network exists sprout-outside >/dev/null 2>&1 || podman network create sprout-outside

echo "(Re)starting egress proxy..."
podman rm -f sprout-egress >/dev/null 2>&1 || true
podman run -d --name sprout-egress \
  --network sprout-inside --network sprout-outside \
  --restart unless-stopped \
  -v "$EGRESS_SRC:/etc/squid/egress:ro" \
  sprout-egress
# Config is mounted, not baked in: a merged allowlist change goes live with
#   "$EGRESS_SRC/reload.sh"   (pull, re-render, squid -k reconfigure)
# (no rebuild, no agent restart).

echo "Starting Sprout (memory ${MEMORY_LIMIT}, cpus ${CPU_LIMIT})..."
exec podman run -it --rm \
  --name sprout \
  --network sprout-inside \
  --env-file "$ENV_FILE" \
  -e HTTP_PROXY=http://sprout-egress:3128 \
  -e HTTPS_PROXY=http://sprout-egress:3128 \
  -e http_proxy=http://sprout-egress:3128 \
  -e https_proxy=http://sprout-egress:3128 \
  --memory "$MEMORY_LIMIT" --cpus "$CPU_LIMIT" --pids-limit 512 \
  -v "$PWD:/home/sprout/sona:Z" \
  -v "$PRIVATE_DIR:/home/sprout/private:Z" \
  sprout
