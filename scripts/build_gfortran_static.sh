#!/usr/bin/env bash
set -euxo pipefail

GCC_VER=${1:-11.3.0}
TARGET_ARCH=${2:-x86_64}
BUILD_ARCH=${3:-$TARGET_ARCH}
KERN_VER=$([[ $TARGET_ARCH == x86_64 ]] && echo 13.4.0 || echo 20.0.0)
TRIPLE="${TARGET_ARCH}-apple-darwin${KERN_VER}"

WORKDIR=${PWD}
STATIC_ROOT=$WORKDIR/static-root

eval "$(micromamba shell hook -s bash)"
micromamba activate "$WORKDIR/.gcc-static-build"
export PATH="$WORKDIR/.gcc-static-build/bin:/usr/bin:$PATH"
export CC=clang CXX=clang++

export CPPFLAGS="-I$STATIC_ROOT/include"
export LDFLAGS="-L$STATIC_ROOT/lib -static"

curl -Lso "gcc-${GCC_VER}.tar.gz" "https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VER}/gcc-${GCC_VER}.tar.gz"
tar xf "gcc-${GCC_VER}.tar.gz"
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

find "$STATIC_ROOT" -name '*.dylib' -delete
ln -sf ../lib "$STATIC_ROOT/bin/lib"

tar -C "$STATIC_ROOT/.." -czf "gfortran-darwin-${TARGET_ARCH}-${BUILD_ARCH}.static.tar.gz" "$(basename "$STATIC_ROOT")"
echo "Wrote $(pwd)/gfortran-darwin-${TARGET_ARCH}-${BUILD_ARCH}.static.tar.gz"
