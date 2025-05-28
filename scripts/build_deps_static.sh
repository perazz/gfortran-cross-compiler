#!/usr/bin/env bash
set -euxo pipefail

export MAMBA_NO_PROMPT=1
export MAMBA_LOG_LEVEL='debug'

WORKDIR=${PWD}
STATIC_ROOT=$WORKDIR/static-root
mkdir -p "$STATIC_ROOT"

BUILD_ENV_PREFIX="$WORKDIR/.gcc-static-build"
rm -rf "$BUILD_ENV_PREFIX"

eval "$(micromamba shell hook -s bash)"

micromamba create -y -p "$BUILD_ENV_PREFIX" -c conda-forge \
  clang lld \
  make cmake \
  autoconf automake libtool \
  pkg-config texinfo \
  patch curl ca-certificates git

micromamba activate "$BUILD_ENV_PREFIX"
export PATH="$BUILD_ENV_PREFIX/bin:/usr/bin:$PATH"
export CC=clang CXX=clang++

build_one () {
  local pkg=$1 ver=$2 filnm=$3
  shift 3
  local cfg_extra=("$@")
  
  ext="${filnm##*.}"
  tarball="${pkg}-${ver}.${ext}"
  src_tar="downloads/${tarball}"
  
  if [[ ! -f "$src_tar" ]]; then
    echo "ERROR: $src_tar not found."
    exit 1
  fi

  cp "$src_tar" .
  tar xf "$tarball"
  pushd "${pkg}-${ver}"
    ./configure --prefix="$STATIC_ROOT" --enable-static --disable-shared "${cfg_extra[@]}"  
    make -j"$(sysctl -n hw.ncpu)"
    make install
  popd
}

build_one gmp   6.3.0  "gmp-6.3.0.gz"   ""
build_one mpfr  4.2.1  "mpfr-4.2.1.gz"  "--with-gmp=$STATIC_ROOT"
build_one mpc   1.3.1  "mpc-1.3.1.gz"   "--with-gmp=$STATIC_ROOT --with-mpfr=$STATIC_ROOT"
build_one isl   0.26   "isl-0.26.gz"    "--with-gmp=$STATIC_ROOT --with-mpfr=$STATIC_ROOT"
build_one zlib  1.3.1  "zlib-1.3.1.gz"  ""
