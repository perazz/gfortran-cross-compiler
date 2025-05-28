#!/usr/bin/env bash
set -euxo pipefail

source "$(dirname "$0")/activate_mamba.sh"

GCC_VER=${1:-11.3.0}
TARGET_ARCH=${2:-x86_64}
BUILD_ARCH=${3:-$TARGET_ARCH}
KERN_VER=$([[ $TARGET_ARCH == x86_64 ]] && echo 13.4.0 || echo 20.0.0)
TRIPLE="${TARGET_ARCH}-apple-darwin${KERN_VER}"

GCC_TARBALL="gcc-${GCC_VER}.tar.gz"
GCC_URLS=(
  "https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VER}/${GCC_TARBALL}"
  "https://ftpmirror.gnu.org/gcc/gcc-${GCC_VER}/${GCC_TARBALL}"
)

# Try each URL with retries
for url in "${GCC_URLS[@]}"; do
  echo "Attempting download from $url"
  if curl -L --retry 5 --retry-delay 3 -o "$GCC_TARBALL" "$url"; then
    break
  else
    echo "Failed to download from $url"
  fi
done

# Check result
if [[ ! -f "$GCC_TARBALL" ]]; then
  echo "ERROR: Failed to download GCC tarball from all sources"
  exit 1
fi

# Continue as before
tar xf "$GCC_TARBALL"
mkdir gcc-build && cd gcc-build

echo "CC = $CC"
echo "CXX = $CXX"
echo "CFLAGS = $CFLAGS"
echo "CXXFLAGS = $CXXFLAGS"
echo "LDFLAGS = $LDFLAGS"

../gcc-${GCC_VER}/configure \
  --build="${BUILD_ARCH}-apple-darwin$(uname -r)" \
  --host="${BUILD_ARCH}-apple-darwin$(uname -r)" \
  --target="$TRIPLE" \
  --prefix="$STATIC_ROOT" \
  --with-sysroot="$SDKROOT" \
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
