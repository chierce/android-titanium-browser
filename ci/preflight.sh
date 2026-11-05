#!/usr/bin/env bash
# Preflight for a Chromium-for-Android build.
# Chromium's own docs ask for >= 100 GB free; an Android official build with
# two ABIs lands closer to 120-150 GB once out/ is populated. Fail early and
# loudly instead of dying at hour three inside ninja.
set -euo pipefail

REQUIRED_GB=${REQUIRED_GB:-120}
DIR=${1:-.}

die() { printf '\033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }
ok()  { printf '\033[32m✓ %s\033[0m\n' "$*"; }
warn(){ printf '\033[33m! %s\033[0m\n' "$*"; }

# ---- disk ------------------------------------------------------------------
free_gb=$(df -Pk "$DIR" | awk 'NR==2 {printf "%d", $4/1024/1024}')
total_gb=$(df -Pk "$DIR" | awk 'NR==2 {printf "%d", $2/1024/1024}')
printf 'disk at %s: %s GB free of %s GB\n' "$DIR" "$free_gb" "$total_gb"
if [ "$free_gb" -lt "$REQUIRED_GB" ]; then
  die "need ${REQUIRED_GB} GB free, have ${free_gb} GB. Free space or use a self-hosted runner with a bigger volume."
fi
ok "disk budget"

# ---- cpu / ram -------------------------------------------------------------
cores=$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 0)
mem_gb=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo 0)
printf 'cpu: %s cores, ram: %s GB\n' "$cores" "$mem_gb"
[ "$mem_gb" -ge 8 ] || warn "under 8 GB RAM: the final link step will thrash or OOM"
[ "$cores" -ge 4 ]  || warn "under 4 cores: expect a multi-hour build"

# ---- toolchain -------------------------------------------------------------
for bin in git python3 curl; do
  command -v "$bin" >/dev/null || die "missing $bin"
done
ok "basic toolchain"

# ---- android sdk deps that bite on plain ubuntu ----------------------------
missing=""
for pkg in lsb-release file imagemagick librsvg2-bin; do
  dpkg -s "$pkg" >/dev/null 2>&1 || missing="$missing $pkg"
done
if [ -n "$missing" ]; then
  warn "apt packages missing:$missing"
  warn "build.sh installs these itself (needs sudo)"
else
  ok "apt packages present"
fi

# ---- chromium source already present? --------------------------------------
if [ -d chromium/src/out/Default ]; then
  ok "existing out/Default found - incremental build possible"
else
  warn "no out/Default: this run pays the full gclient sync + first-compile cost"
fi

printf '\npreflight passed. expected wall clock: 2-6 h on %s cores, single ABI.\n' "$cores"