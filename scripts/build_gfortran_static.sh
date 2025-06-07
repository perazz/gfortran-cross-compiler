#!/usr/bin/env bash
set -euxo pipefail
set -x # trace every command

GCC_VER=${1:-11.3.0}
TARGET_ARCH=${2:-x86_64}
BUILD_ARCH=${3:-$TARGET_ARCH}

source "$(dirname "$0")/activate_mamba.sh" "$TARGET_ARCH" "$BUILD_ARCH"

# Use locally-uploaded release artifact
GCC_TARBALL="$TOPDIR/downloads/gcc-${GCC_VER}.tar.gz"
if [[ ! -r "$GCC_TARBALL" ]]; then
  echo "ERROR: gcc tarball not found at $GCC_TARBALL"
  exit 1
fi

# Extract GCC tarball
tar -C . -xf "$GCC_TARBALL"

# Normalize extracted directory name if needed (GitHub mirror creates 'gcc-releases-gcc-<ver>')
if [[ -d "gcc-releases-gcc-${GCC_VER}" ]]; then
  mv "gcc-releases-gcc-${GCC_VER}" "gcc-${GCC_VER}"
fi

# patches
patch -p1 -d "gcc-${GCC_VER}" < "$SCRIPT_DIR/emutls.patch"

# Proceed to build directory
mkdir build && cd build

echo "CC = $CC"
echo "CXX = $CXX"
echo "CFLAGS = $CFLAGS"
echo "CXXFLAGS = $CXXFLAGS"
echo "LDFLAGS = $LDFLAGS"

echo "Testing clang++:"
$CXX --version || { echo "clang++ not found or not executable"; exit 1; }

echo "Testing C++11 support:"
echo 'int main() { auto x = 42; return x; }' | $CXX -std=c++11 -x c++ -o /tmp/test-cxx11 - || { echo "C++11 test failed"; exit 1; }

# Save original host build flags (e.g. Clang flags from Conda)
ORIG_CXXFLAGS="$CXXFLAGS"

# locate Apple's binutils via xcrun
export AS_FOR_TARGET=$(xcrun -f as)
export LD_FOR_TARGET=$(xcrun -f ld)
export AR_FOR_TARGET=$(xcrun -f ar)
export RANLIB_FOR_TARGET=$(xcrun -f ranlib)

export CONFIG_SITE="$SCRIPT_DIR/config.site"

../gcc-${GCC_VER}/configure \
  --build="${BUILD_ARCH}-apple-darwin" \
  --host="${BUILD_ARCH}-apple-darwin" \
  --target="${TRIPLE}" \
  --prefix="${STATIC_ROOT}" \
  --with-sysroot="${SDKROOT}" \
  --enable-threads=posix \
  --disable-multilib \
  --disable-nls \
  --disable-shared \
  --enable-static \
  --enable-languages=c,c++,fortran \
  --with-build-system=ninja \
  --with-gmp-include="${STATIC_ROOT}/include" \
  --with-gmp-lib="${STATIC_ROOT}/lib" \
  --with-mpfr-include="${STATIC_ROOT}/include" \
  --with-mpfr-lib="${STATIC_ROOT}/lib" \
  --with-mpc-include="${STATIC_ROOT}/include" \
  --with-mpc-lib="${STATIC_ROOT}/lib" \
  --with-isl="${STATIC_ROOT}" \
  --with-system-zlib \
  CFLAGS_FOR_TARGET="${CFLAGS_FOR_TARGET}" \
  CXXFLAGS_FOR_TARGET="${CXXFLAGS_FOR_TARGET}" \
  LDFLAGS_FOR_TARGET="${LDFLAGS_FOR_TARGET}"
      
make -j"$(sysctl -n hw.ncpu)" \
  all-gcc \
  all-target-libgcc \
  all-target-libgfortran \
  all-target-libquadmath
    
# gcc bug in CXXFLAGS mismatch
make -j"$(sysctl -n hw.ncpu)" \
  all-target-libstdc++-v3 \
  CXXFLAGS="$CXXFLAGS_FOR_TARGET"    
    
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

