#!/usr/bin/env bash
set -euxo pipefail
set -x # trace every command

source "$(dirname "$0")/activate_mamba.sh"

GCC_VER=${1:-11.3.0}
TARGET_ARCH=${2:-x86_64}
BUILD_ARCH=${3:-$TARGET_ARCH}
KERN_VER=$([[ $TARGET_ARCH == x86_64 ]] && echo 13.4.0 || echo 20.0.0)
TRIPLE="${TARGET_ARCH}-apple-darwin${KERN_VER}"

GCC_TARBALL="gcc-${GCC_VER}.tar.gz"
GCC_URLS=(
  "https://github.com/gcc-mirror/gcc/archive/refs/tags/releases/gcc-${GCC_VER}.tar.gz"
  "https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VER}/gcc-${GCC_VER}.tar.gz"
  "https://ftpmirror.gnu.org/gcc/gcc-${GCC_VER}/gcc-${GCC_VER}.tar.gz"
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

# Extract GCC tarball
tar xf "$GCC_TARBALL"

# Normalize extracted directory name if needed (GitHub mirror creates 'gcc-releases-gcc-<ver>')
if [[ -d "gcc-releases-gcc-${GCC_VER}" ]]; then
  mv "gcc-releases-gcc-${GCC_VER}" "gcc-${GCC_VER}"
fi

# Proceed to build directory
mkdir gcc-build && cd gcc-build

echo "CC = $CC"
echo "CXX = $CXX"
echo "CFLAGS = $CFLAGS"
echo "CXXFLAGS = $CXXFLAGS"
echo "LDFLAGS = $LDFLAGS"

echo "Testing clang++:"
$CXX --version || { echo "clang++ not found or not executable"; exit 1; }

echo "Testing C++11 support:"
echo 'int main() { auto x = 42; return x; }' | $CXX -std=c++11 -x c++ -o /tmp/test-cxx11 - || { echo "C++11 test failed"; exit 1; }

export CPPFLAGS="${CPPFLAGS:-} -I$STATIC_ROOT/include"
export LDFLAGS="${LDFLAGS:-} -L$STATIC_ROOT/lib -Wl,-syslibroot,$SDKROOT"

../gcc-${GCC_VER}/configure \
  --build="${BUILD_ARCH}-apple-darwin$(uname -r)" \
  --host="${BUILD_ARCH}-apple-darwin$(uname -r)" \
  --target="$TRIPLE" \
  --prefix="$STATIC_ROOT" \
  --with-sysroot="$SDKROOT" \
  --enable-languages=c,c++,fortran \
  --disable-shared --enable-static \
  --disable-multilib --disable-nls \
  --with-gmp-include="$STATIC_ROOT/include" \
  --with-gmp-lib="$STATIC_ROOT/lib" \
  --with-mpfr-include="$STATIC_ROOT/include" \
  --with-mpfr-lib="$STATIC_ROOT/lib" \
  --with-mpc-include="$STATIC_ROOT/include" \
  --with-mpc-lib="$STATIC_ROOT/lib" \
  --with-isl="$STATIC_ROOT" \
  --with-system-zlib \
  CFLAGS_FOR_TARGET="-O2" \
  CXXFLAGS_FOR_TARGET="-O2" \
  LDFLAGS_FOR_TARGET="-static"

make -j"$(sysctl -n hw.ncpu)" all-gcc all-target-libgcc all-target-libgfortran all-target-libquadmath
make install-strip
cd ..

find "$STATIC_ROOT" -name '*.dylib' -delete
ln -sf ../lib "$STATIC_ROOT/bin/lib"

echo ">>> STATIC_ROOT is: $STATIC_ROOT"
echo ">>> Listing install tree:"
ls -R "$STATIC_ROOT"

echo ">>> Now packaging into tarball…"
tarball="gfortran-darwin-${TARGET_ARCH}-${BUILD_ARCH}.static.tar.gz"
tar -C "$(dirname "$STATIC_ROOT")" -czf "$TOPDIR/$tarball" "$(basename "$STATIC_ROOT")"
echo "Wrote $TOPDIR/$tarball"

