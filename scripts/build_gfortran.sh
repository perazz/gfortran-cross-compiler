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
# make arch and type part of the environment so the sub-shell can see them
export arch type

micromamba run -n "gfortran-darwin-$arch-$type" bash <<'EOF'
set -euxo pipefail

# ── discover paths dynamically ────────────────────────────────────────────
triplet=\$(gfortran -dumpmachine)                # e.g. arm64-apple-darwin20.0.0
gcc_ver=\$(gfortran -dumpfullversion)            # e.g. 14.2.0
gcc_dir="\$CONDA_PREFIX/libexec/gcc/\$triplet/\$gcc_ver"

# ── prune bulky/unused files ─────────────────────────────────────────────
rm -rf "\$CONDA_PREFIX"/lib/{libc++*,*.a,pkgconfig,clang}

# ── move runtime libs next to the compiler (needed only when cross) ──────
if [[ "\$type" == "cross" ]]; then
  mv "\$CONDA_PREFIX"/lib/{libgfortran*,libgomp*,libomp*,libgcc_s*,libquadmath*} "\$gcc_dir" || true
fi

# ── fix rpath for libgcc_s only if the file exists ───────────────────────
if [[ -f "\$CONDA_PREFIX/lib/libgcc_s.1.dylib" ]]; then
  install_name_tool -change "\$CONDA_PREFIX/lib/libgcc_s.1.1.dylib" \
                    '@rpath/libgcc_s.1.1.dylib' \
                    "\$CONDA_PREFIX/lib/libgcc_s.1.dylib" || true
fi

# ── package the entire environment ───────────────────────────────────────
pkg_dir=\$(basename "\$CONDA_PREFIX")            # gfortran-darwin-arm64-native
pushd "\$(dirname "\$CONDA_PREFIX")"
tar -czf "\${pkg_dir}.tar.gz" "\$pkg_dir"
popd
EOF

# move the tar-ball next to the script so upload-artifact can find it
pkg_file=\$(basename "\$CONDA_PREFIX").tar.gz
mv "\$(dirname "\$CONDA_PREFIX")/\$pkg_file" .


mv "$HOME/micromamba/envs/gfortran-darwin-$arch-$type/../gfortran-darwin-$arch-$type.tar.gz" .
