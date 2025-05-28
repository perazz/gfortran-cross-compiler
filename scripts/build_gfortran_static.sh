#!/usr/bin/env bash
set -euo pipefail

#--------------------------- 1. Parse CLI -------------------------------
GCC_VER=${1:-${GFORTRAN_VERSION:-11.3.0}}
TARGET_ARCH=${2:-${TARGET_ARCH:-x86_64}}          # arm64 or x86_64
BUILD_ARCH=${3:-${BUILD_ARCH:-${TARGET_ARCH}}}   # usually same as host

KERN_VER=$([[ $TARGET_ARCH == x86_64 ]] && echo 13.4.0 || echo 20.0.0)
TRIPLE="${TARGET_ARCH}-apple-darwin${KERN_VER}"

WORKDIR=${PWD}
STATIC_ROOT=$WORKDIR/static-root
mkdir -p "$STATIC_ROOT"

#--------------------------- 2. Bootstrap env ---------------------------
eval "$(micromamba shell hook -s bash)"
micromamba create -y -n gcc-static-build \
  clang \
  lld \
  gnu-binutils \
  make cmake autoconf automake libtool \
  gmp-devel-static mpfr-devel-static mpc-devel-static isl-static zlib-static

micromamba activate gcc-static-build
export PATH=$CONDA_PREFIX/bin:$PATH
export CC=clang CXX=clang++

# strip out .dylibs from the bootstrap libs so we don’t acci­dentally pick them up
find "$CONDA_PREFIX/lib" -name '*.dylib' -delete

#--------------------------- 3. Build static prerequisites --------------
build_one () {
  local pkg=$1 ver=$2 url=$3 cfg_extra=$4
  curl -Lso "${pkg}-${ver}.tar.gz" "$url"
  tar xf "${pkg}-${ver}.tar.gz"
  pushd "${pkg}-${ver}"
    ./configure --prefix="$STATIC_ROOT" --enable-static --disable-shared $cfg_extra
    make -j"$(sysctl -n hw.ncpu)"
    make install
  popd
}
build_one gmp   6.3.0  "https://gmplib.org/download/gmp/gmp-6.3.0.tar.xz"   ""
build_one mpfr  4.2.1  "https://www.mpfr.org/mpfr-4.2.1/mpfr-4.2.1.tar.xz"  "--with-gmp=$STATIC_ROOT"
build_one mpc   1.3.1  "https://ftp.gnu.org/gnu/mpc/mpc-1.3.1.tar.gz"        "--with-gmp=$STATIC_ROOT --with-mpfr=$STATIC_ROOT"
build_one isl   0.26   "http://isl.gforge.inria.fr/isl-0.26.tar.xz"          ""
build_one zlib  1.3.1  "https://zlib.net/zlib-1.3.1.tar.xz"                  ""

export CPPFLAGS="-I$STATIC_ROOT/include"
export LDFLAGS="-L$STATIC_ROOT/lib -static"

#--------------------------- 4.   Build GCC   ---------------------------
curl -Lso "gcc-${GCC_VER}.tar.xz" "https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VER}/gcc-${GCC_VER}.tar.xz"
tar xf "gcc-${GCC_VER}.tar.xz"
mkdir gcc-build && cd gcc-build

../gcc-${GCC_VER}/configure \
  --build="${BUILD_ARCH}-apple-darwin$(uname -r)" \
  --host="${BUILD_ARCH}-apple-darwin$(uname -r)" \
  --target="$TRIPLE" \
  --prefix="$STATIC_ROOT" \
  --with-sysroot=/ \
  --enable-languages=c,c++,fortran \
  --disable-shared --enable-static \
  --disable-multilib --disable-nls \
  --with-gmp="$STATIC_ROOT" \
  --with-mpfr="$STATIC_ROOT" \
  --with-mpc="$STATIC_ROOT" \
  --with-isl="$STATIC_ROOT" \
  --with-zlib="$STATIC_ROOT" \
  CFLAGS_FOR_TARGET="-O2" \
  CXXFLAGS_FOR_TARGET="-O2" \
  LDFLAGS_FOR_TARGET="-static"

make -j"$(sysctl -n hw.ncpu)" all-gcc all-target-libgcc all-target-libgfortran all-target-libquadmath
make install-strip
cd ..

#--------------------------- 5. Clean tree ------------------------------
# no shared libs anywhere
find "$STATIC_ROOT" -name '*.dylib' -delete

# symbolic link so @loader_path/../../../../lib resolves for cc1
ln -sf ../lib "$STATIC_ROOT/bin/lib"

#--------------------------- 6. Pack ------------------------------------
tar -C "$STATIC_ROOT/.." -czf "gfortran-darwin-${TARGET_ARCH}-${BUILD_ARCH}.static.tar.gz" "$(basename "$STATIC_ROOT")"
echo "Wrote $(pwd)/gfortran-darwin-${TARGET_ARCH}-${BUILD_ARCH}.static.tar.gz"
