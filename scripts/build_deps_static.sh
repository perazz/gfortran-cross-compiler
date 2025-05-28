#!/usr/bin/env bash
set -euxo pipefail

if [[ -z "${MAMBA_DEFAULT_ENV:-}" ]]; then
  source "$(dirname "$0")/activate_mamba.sh"
fi

export CC=clang CXX=clang++

build_one () {
  local pkg=$1 ver=$2 filnm=$3
  shift 3
  local -a cfg_extra=()
  [[ $# -gt 0 ]] && cfg_extra=("$@")

  local ext="${filnm##*.}"
  local tarball="${pkg}-${ver}.${ext}"
  local src_tar="downloads/${tarball}"

  if [[ ! -f "$src_tar" ]]; then
    echo "ERROR: $src_tar not found."
    exit 1
  fi

  cp "$src_tar" .
  tar xf "$tarball"
  pushd "${pkg}-${ver}"
    
    if [[ "$pkg" == "zlib" ]]; then
      ./configure --prefix="$STATIC_ROOT" --static
    else
      ./configure --prefix="$STATIC_ROOT" --enable-static --disable-shared "${cfg_extra[@]}"
    fi
    make -j"$(sysctl -n hw.ncpu)"
    make install
    
  popd
}


build_one gmp   6.3.0  "gmp-6.3.0.gz"   ""
build_one mpfr  4.2.1  "mpfr-4.2.1.gz"  "--with-gmp=$STATIC_ROOT"
build_one mpc   1.3.1  "mpc-1.3.1.gz"   "--with-gmp=$STATIC_ROOT" "--with-mpfr=$STATIC_ROOT"
build_one isl   0.26   "isl-0.26.gz"    "--with-int=gmp" "--with-gmp-prefix=$STATIC_ROOT"
build_one zlib  1.3.1  "zlib-1.3.1.gz"  ""
