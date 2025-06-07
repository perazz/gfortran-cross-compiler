#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
# 0. Environment setup
# ─────────────────────────────────────────────
BUILD_ARCH=arm64
TARGET_ARCH=x86_64
GCC_VERSION=14.2.0
KERN_VER=13.4.0
TRIPLE="${TARGET_ARCH}-apple-darwin${KERN_VER}"
TOPDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export WORKDIR="$TOPDIR"
export STATIC_ROOT="$TOPDIR/static-root"
export BUILD_ENV_PREFIX="$TOPDIR/.gcc-static-build"

# ─────────────────────────────────────────────
# 1. Activate micromamba
# ─────────────────────────────────────────────
eval "$(micromamba shell hook --shell bash)"
bash "$TOPDIR/scripts/setup_mamba_env.sh"

# ─────────────────────────────────────────────
# 2. Download static prerequisites
# ─────────────────────────────────────────────
mkdir -p "$TOPDIR/downloads"
cd "$TOPDIR"
BASE_URL="https://github.com/perazz/gfortran-cross-compiler/releases/download/static-prereqs-v1"

pkgs=(
  gmp-6.3.0
  mpfr-4.2.1
  mpc-1.3.1
  isl-0.26
  zlib-1.3.1
  gcc-${GCC_VERSION}.tar
)

for pkg in "${pkgs[@]}"; do
  dst="downloads/${pkg}.gz"

  if [[ -f "$dst" ]]; then
    echo "✅ ${dst} already exists – skipping."
    continue
  fi

  echo "📦 Downloading ${pkg}.gz..."
  #  -L   follow redirects
  #  -C - resume if a partial file is already there
  #  --retry 3  re-try transient network failures
  #  --fail     make curl exit non-zero on HTTP errors
  curl -L -C - --retry 3 --fail -o "$dst" "$BASE_URL/${pkg}.gz"
done

# ─────────────────────────────────────────────
# 3. Install and check static prerequisites
# ─────────────────────────────────────────────
bash "$TOPDIR/scripts/build_deps_static.sh"
bash "$TOPDIR/scripts/check_static_deps.sh"

# ─────────────────────────────────────────────
# 4. Build the compiler
# ─────────────────────────────────────────────
mkdir -p "$TOPDIR/gcc-build"
cd "$TOPDIR/gcc-build"

echo "⚙️  Building gfortran..."
{
  bash "$TOPDIR/scripts/build_gfortran_static.sh" "$GCC_VERSION" "$TARGET_ARCH" "$BUILD_ARCH"
} 2>&1 | tee "$TOPDIR/configure-output.log"

if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
  echo "❌ Configure or build failed. See logs."
  exit 1
fi

# ─────────────────────────────────────────────
# 5. Dump config logs if any
# ─────────────────────────────────────────────
echo "📄 configure-output.log:"
cat "$TOPDIR/configure-output.log" || true

echo "🔍 Recursively dumping config.log files:"
find . -name config.log -exec echo "──── {} ────" \; -exec cat {} \; || true

# ─────────────────────────────────────────────
# 6. Test built gfortran
# ─────────────────────────────────────────────
cd "$TOPDIR"
bash "$TOPDIR/scripts/test_gfortran.sh" "$BUILD_ARCH" "$TARGET_ARCH" "$STATIC_ROOT"

# ─────────────────────────────────────────────
# 7. Compute SHA-256 checksum
# ─────────────────────────────────────────────
TARBALL=$(ls gfortran-darwin-${TARGET_ARCH}-*.tar.gz)
shasum -a 256 "$TARBALL" > \
  "gfortran-${TARGET_ARCH}-${BUILD_ARCH}-${GCC_VERSION}.sha256"
echo "📦 Tarball: $TARBALL"
echo "🔐 SHA256:"
cat "gfortran-${TARGET_ARCH}-${BUILD_ARCH}-${GCC_VERSION}.sha256"

echo "✅ Done."

