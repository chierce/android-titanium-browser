#!/usr/bin/env bash
# arm64-only mirror of build.sh.
# Differences from upstream build.sh, all deliberate:
#   - one pass instead of two (no armeabi-v7a APK, halves the wall clock)
#   - target_cpu is arm64 from the start (build.sh starts at arm, then sed's it)
#   - stops after autoninja; signing is a separate, explicit step
# Everything else (patch pruning, branding replace, gclient sync, patch.sh) is
# copied verbatim so the produced build matches upstream intent.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$SCRIPT_DIR"
export SCRIPT_DIR   # common.sh recomputes SCRIPT_DIR from $0, which is ci/ here — pin it before sourcing
source common.sh
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$SCRIPT_DIR"

MAX_JOBS=${MAX_JOBS:-10}
LOG() { printf '\n=== [%s] %s ===\n' "$(date +%H:%M:%S)" "$*"; }

export DEBIAN_FRONTEND=noninteractive
export VERSION=$(grep -m1 -oE '[0-9]+(\.[0-9]+){3}' vanadium/args.gn)
export CHROMIUM_SOURCE=https://chromium.googlesource.com/chromium/src.git
LOG "Titanium build for Chromium $VERSION, arm64 only, MAX_JOBS=$MAX_JOBS"

# ---------------------------------------------------------------- 1. deps
LOG "apt dependencies"
sudo apt-get update -qq
sudo apt-get install -y -qq sudo lsb-release file nano git curl python3 python3-pillow imagemagick librsvg2-bin
sudo dpkg --add-architecture i386
sudo apt-get update -qq
sudo apt-get install -y -qq libgcc-s1:i386

# ------------------------------------------------------------ 2. depot_tools
if [ ! -d depot_tools ]; then
  LOG "cloning depot_tools"
  git clone --depth 1 https://chromium.googlesource.com/chromium/tools/depot_tools.git
fi
export PATH="$SCRIPT_DIR/depot_tools:$PATH"

# ------------------------------------------------------- 3. chromium checkout
mkdir -p chromium/src/out/Default
cd chromium/src
if [ ! -d .git ]; then
  LOG "fetching chromium $VERSION (shallow tag)"
  git init -q
  git remote add origin "$CHROMIUM_SOURCE"
  git fetch --depth 1 "$CHROMIUM_SOURCE" "+refs/tags/$VERSION:chromium_$VERSION"
  git checkout -q "$VERSION"
fi
cp "$SCRIPT_DIR/.gclient" ../.gclient

# ------------------------------------------- 4. Vanadium patch set, pruned
LOG "pruning patch set (same removals as build.sh)"
cd "$SCRIPT_DIR"
rm -f vanadium/patches/*trichrome-{apk-build-targets,browser-apk-targets}.patch
rm -f vanadium/patches/*{detailed,supported}-language*.patch
rm -f vanadium/patches/*javascript-optimizer-{site-setting,settings-UI}.patch
rm -f vanadium/patches/*component-updates.patch
rm -f vanadium/patches/*{pdf,PDF,for-content-public,toolbar-button,configs-from-config-app,config-app-parsing,new-tab-card,predictive-back}*.patch
replace "$SCRIPT_DIR/vanadium/patches" "VANADIUM" "TITANIUM"
replace "$SCRIPT_DIR/vanadium/patches" "Vanadium" "Titanium"
replace "$SCRIPT_DIR/vanadium/patches" "vanadium" "titanium"

cd chromium/src
LOG "applying $(ls "$SCRIPT_DIR"/vanadium/patches/*.patch | wc -l) patches"
git am --whitespace=nowarn --keep-non-patch "$SCRIPT_DIR"/vanadium/patches/*.patch

# ------------------------------------------------------------- 5. gclient sync
LOG "gclient sync (this is the ~40-60 GB download)"
gclient sync -D --no-history --nohooks
gclient runhooks
sudo ./build/install-build-deps.sh --no-prompt

# ------------------------------------------------------------- 6. configure
LOG "patch.sh + gn gen"
source "$SCRIPT_DIR/patch.sh"
cp "$SCRIPT_DIR/args.gn" out/Default/args.gn
sed -i 's/target_cpu = "arm"/target_cpu = "arm64"/' out/Default/args.gn
gn gen out/Default

# ---------------------------------------------------------------- 7. compile
LOG "autoninja chrome_public_apk (the long part)"
autoninja -C out/Default -j "$MAX_JOBS" chrome_public_apk

mkdir -p out/release
APK=$(find out/Default/apks -name 'Chrome*.apk' | head -n1)
cp "$APK" "out/release/$VERSION-arm64-v8a.apk"
LOG "done: chromium/src/out/release/$VERSION-arm64-v8a.apk"
ls -lh "out/release/$VERSION-arm64-v8a.apk"