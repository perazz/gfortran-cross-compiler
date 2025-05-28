#!/usr/bin/env bash

# Resolve the directory of the current script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOPDIR="$(cd "$SCRIPT_DIR/.." && pwd)"

export WORKDIR="$TOPDIR"
export STATIC_ROOT="$TOPDIR/static-root"
export BUILD_ENV_PREFIX="$TOPDIR/.gcc-static-build"

