#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────
# 0. Read arguments
# ──────────────────────────────────────────
TARGET_ARCH="${1:-$(uname -m)}"
BUILD_ARCH="${2:-$(uname -m)}"
KERN_VER=$([[ "$TARGET_ARCH" == "x86_64" ]] && echo 13.4.0 || echo 20.0.0)
TRIPLE="${TARGET_ARCH}-apple-darwin${KERN_VER}"
DEPLOYMENT_TARGET=13.0

# ──────────────────────────────────────────
# 1. Activate micromamba
# ──────────────────────────────────────────
source "$(dirname "$0")/setup_mamba_env.sh"

SHELL_NAME=$(basename "$SHELL")
eval "$(micromamba shell hook --shell=$SHELL_NAME)"

micromamba activate "$BUILD_ENV_PREFIX"

# ──────────────────────────────────────────
# 2. Ensure conda tools are found first
# ──────────────────────────────────────────
export PATH="$BUILD_ENV_PREFIX/bin:/usr/bin:$PATH"

# ──────────────────────────────────────────
# 3. Locate the macOS SDK
# ──────────────────────────────────────────
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"

# ──────────────────────────────────────────
# 4. Build toolchain settings (host side)
# ──────────────────────────────────────────
export CC="$BUILD_ENV_PREFIX/bin/clang"
export CXX="$BUILD_ENV_PREFIX/bin/clang++"
export CFLAGS="-isysroot $SDKROOT -mmacosx-version-min=$DEPLOYMENT_TARGET"
export CXXFLAGS="$CFLAGS -std=c++11"
export LDFLAGS="-Wl,-syslibroot,$SDKROOT"

# ──────────────────────────────────────────
# 5. Target-specific flags for cross-compiling
# ──────────────────────────────────────────
ARCH_FLAG="-arch $TARGET_ARCH"

export CFLAGS_FOR_TARGET="-O2 -isysroot $SDKROOT -mmacosx-version-min=$DEPLOYMENT_TARGET $ARCH_FLAG"
export CXXFLAGS_FOR_TARGET="-O2 -isysroot $SDKROOT -mmacosx-version-min=$DEPLOYMENT_TARGET $ARCH_FLAG -std=c++11"
export LDFLAGS_FOR_TARGET="-static -Wl,-syslibroot,$SDKROOT $ARCH_FLAG"

# ──────────────────────────────────────────
# 6. Export triple for use in other scripts
# ──────────────────────────────────────────
export TARGET_ARCH
export BUILD_ARCH
export TRIPLE
