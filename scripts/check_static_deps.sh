#!/usr/bin/env bash
set -euo pipefail

STATIC_ROOT=${STATIC_ROOT:-"$PWD/static-root"}

echo "Checking headers..."
for h in gmp.h mpfr.h mpc.h isl/version.h zlib.h; do
  test -f "$STATIC_ROOT/include/$h" || { echo "Missing header: $h"; exit 1; }
done

echo "Checking static libraries..."
for lib in libgmp.a libmpfr.a libmpc.a libisl.a libz.a; do
  test -f "$STATIC_ROOT/lib/$lib" || { echo "Missing library: $lib"; exit 1; }
done

echo "Inspecting libgmp.a symbols..."
nm "$STATIC_ROOT/lib/libgmp.a" || echo "nm failed"
nm "$STATIC_ROOT/lib/libgmp.a" | grep -q '__gmpz_init' || { echo "libgmp.a missing expected symbol"; exit 1; }

echo "✅ Static prerequisite installation verified"
