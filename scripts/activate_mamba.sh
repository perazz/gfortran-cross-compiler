#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/setup_mamba_env.sh"

eval "$(micromamba shell hook -s bash)"
micromamba activate "$BUILD_ENV_PREFIX"

export PATH="$BUILD_ENV_PREFIX/bin:/usr/bin:$PATH"
export CC=clang
export CXX=clang++
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
