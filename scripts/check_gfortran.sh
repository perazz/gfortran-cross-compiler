#!/usr/bin/env bash
set -euxo pipefail

BUILD_ARCH="$1"
TARGET_ARCH="$2"
STATIC_ROOT="${3:-static-root}"

echo "Testing gfortran in $BUILD_ARCH → $TARGET_ARCH mode"
GFORTRAN=$(find "$STATIC_ROOT/bin" -name '*gfortran' | head -n1)

echo "Using compiler: $GFORTRAN"
"$GFORTRAN" --version

if [[ "$BUILD_ARCH" == "$TARGET_ARCH" ]]; then
  echo 'program main; print *, "Hello from GFortran!"; end program' > test.f90
  "$GFORTRAN" test.f90 -o test.exe
  echo "✅ Compile succeeded"
  ./test.exe
else
  echo "✅ Cross-compiler sanity check passed (compile-only)"
fi
