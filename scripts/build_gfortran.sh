#!/usr/bin/env bash
set -euxo pipefail

# ── matrix inputs with sane fallbacks ──────────────────────────────
ver="${GFORTRAN_VERSION:-14.2.0}"      # GCC release
arch="${TARGET_ARCH:-x86_64}"          # target ISA
native="$(uname -m)"                   # runner’s ISA

# ── resolve conda sub-dirs ────────────────────────────────────────
case "$arch" in
  x86_64) CONDA_HOST_SUBDIR="osx-64" ;;
  arm64)  CONDA_HOST_SUBDIR="osx-arm64" ;;
  *)      echo "Unsupported arch: $arch" >&2; exit 1 ;;
esac

case "$(uname -m)" in
  x86_64) CONDA_BUILD_SUBDIR="osx-64" ;;
  arm64)  CONDA_BUILD_SUBDIR="osx-arm64" ;;
  *)      echo "Unsupported build arch" >&2; exit 1 ;;
esac
type=$([[ "$arch" == "$native" ]] && echo native || echo cross)

# ── create env & install compiler + runtime ───────────────────────
CONDA_SUBDIR=$CONDA_BUILD_SUBDIR micromamba create -y -n gfortran-darwin-$arch-$type \
        gfortran_impl_${CONDA_HOST_SUBDIR}=$ver \
        libgfortran-devel_${CONDA_HOST_SUBDIR}=$ver

CONDA_SUBDIR=$CONDA_HOST_SUBDIR  micromamba install -y -n gfortran-darwin-$arch-$type \
        libgfortran5=$ver


       
# ── inside the env: prune, patch, pack ────────────────────────────
micromamba run -n "gfortran-darwin-$arch-$type" bash <<'EOF'
set -euxo pipefail
triplet=$(gfortran -dumpmachine)
gcc_ver=$(gfortran -dumpfullversion)
gcc_dir="$CONDA_PREFIX/libexec/gcc/$triplet/$gcc_ver"

rm -rf $CONDA_PREFIX/lib/{libc++*,*.a,pkgconfig,clang}
find $CONDA_PREFIX/lib -maxdepth 1 -name "libgfortran*.dylib" -exec mv {} "$gcc_dir" \;
ln -sf /usr/bin/ld "$gcc_dir/ld" || true
install_name_tool -change "$CONDA_PREFIX/lib/libgcc_s.1.1.dylib" '@rpath/libgcc_s.1.1.dylib' \
                  "$CONDA_PREFIX/lib/libgcc_s.1.dylib" || true

pkg_name="gfortran-darwin-${triplet%%-*}-${triplet#*-*-}-cross"  # x86_64 or arm64
pushd "$CONDA_PREFIX/.."
tar -czf "${pkg_name}.tar.gz" "$pkg_name"
popd
EOF

mv "$HOME/micromamba/envs/gfortran-darwin-$arch-$type/../gfortran-darwin-$arch-$type.tar.gz" .
