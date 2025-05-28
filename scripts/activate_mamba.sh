#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────
# 1. activate the micromamba environment
# ──────────────────────────────────────────
source "$(dirname "$0")/setup_mamba_env.sh"

eval "$(micromamba shell hook -s bash)"
micromamba activate "$BUILD_ENV_PREFIX"

# ──────────────────────────────────────────
# 2. ensure conda tools are found first
# ──────────────────────────────────────────
export PATH="$BUILD_ENV_PREFIX/bin:/usr/bin:$PATH"

# ──────────────────────────────────────────
# 3. locate the macOS SDK once
# ──────────────────────────────────────────
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"

# ──────────────────────────────────────────
# 4. tell conda-forge Clang to use that SDK
#    (plus a sensible deployment target)
# ──────────────────────────────────────────
export CC="$BUILD_ENV_PREFIX/bin/clang -isysroot $SDKROOT -mmacosx-version-min=11.0"
export CXX="$BUILD_ENV_PREFIX/bin/clang++ -isysroot $SDKROOT -mmacosx-version-min=11.0"

