#!/usr/bin/env bash
set -euxo pipefail

source "$(dirname "$0")/setup_env.sh"

export MAMBA_NO_PROMPT=1
#export MAMBA_LOG_LEVEL='debug'

rm -rf "$BUILD_ENV_PREFIX"
mkdir -p "$STATIC_ROOT"

eval "$(micromamba shell hook -s bash)"

micromamba create -y -p "$BUILD_ENV_PREFIX" -c conda-forge \
  clang lld \
  make cmake \
  autoconf automake libtool \
  pkg-config texinfo \
  patch curl ca-certificates git
