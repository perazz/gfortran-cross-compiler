#!/usr/bin/env bash
set -euxo pipefail

# let “micromamba activate …” work in this subshell
eval "$(micromamba shell hook -s bash)"

# ── 1. Pick up values from either CLI *or* exported env vars ────────────────
#    (The workflow already sets GFORTRAN_VERSION / TARGET_ARCH.)
ver=${1:-${GFORTRAN_VERSION:-11.3.0}}
arch=${2:-${TARGET_ARCH:-x86_64}}
build=${3:-${BUILD_ARCH:-${arch}}}

if [[ "$arch" == "x86_64" ]]; then
  export CONDA_HOST_SUBDIR="osx-64"
  kern_ver=13.4.0
else
  export CONDA_HOST_SUBDIR="osx-arm64"
  kern_ver=20.0.0
fi
if [[ "$build" == "x86_64" ]]; then
  export CONDA_BUILD_SUBDIR="osx-64"
else
  export CONDA_BUILD_SUBDIR="osx-arm64"
fi
if [[ "$arch" == "${build}" ]]; then
  type="native"
else
  type="cross"
fi

# build-arch packages
export CONDA_SUBDIR=$CONDA_BUILD_SUBDIR
micromamba create -n gfortran-darwin-${arch}-${type} \
  gfortran_impl_${CONDA_SUBDIR}=${ver} \
  libgfortran-devel_${CONDA_SUBDIR}=${ver} --yes

# host-arch runtime
export CONDA_SUBDIR=$CONDA_HOST_SUBDIR
micromamba install -n gfortran-darwin-${arch}-${type} \
  libgfortran5=${ver} --yes

# enter the freshly-created env
micromamba activate gfortran-darwin-${arch}-${type}

rm -rf $CONDA_PREFIX/lib/{libc++*,*.a,pkgconfig,clang}
rm -rf $CONDA_PREFIX/{include,conda-meta,bin/iconv}
for f in $CONDA_PREFIX/lib/{libgmp.dylib,libgmpxx.dylib,libisl.dylib,libiconv.dylib,libmpfr.dylib,libz.dylib,libcharset.dylib,libmpc.dylib}; do
  install_name_tool -delete_rpath $CONDA_PREFIX/lib $f || true;
  install_name_tool -delete_rpath $CONDA_PREFIX/lib $f || true;
  rm $f;
done
rm $CONDA_PREFIX/lib/libiomp5.dylib
if [[ "$type" == "cross" ]]; then
  dest=$CONDA_PREFIX/lib/gcc/${arch}-apple-darwin${kern_ver}/${ver}
  mkdir -p "$dest"
  mv $CONDA_PREFIX/lib/{libgfortran*,libgomp*,libomp*,libgcc_s*} "$dest"
fi

# point the compiler’s linker stub at the system ld
execdir=$CONDA_PREFIX/libexec/gcc/${arch}-apple-darwin${kern_ver}/${ver}
mkdir -p "$execdir"                 # make sure it exists in cross builds
ln -sf /usr/bin/ld "$execdir/ld"

sed -i '' "s#-rpath $CONDA_PREFIX/lib##g" $CONDA_PREFIX/lib/gcc/${arch}-apple-darwin${kern_ver}/${ver}/libgfortran.spec
rm $CONDA_PREFIX/libexec/gcc/${arch}-apple-darwin${kern_ver}/${ver}/cc1
mv $CONDA_PREFIX/libexec/gcc/${arch}-apple-darwin${kern_ver}/${ver}/cc1.bin $CONDA_PREFIX/libexec/gcc/${arch}-apple-darwin${kern_ver}/${ver}/cc1
pushd $CONDA_PREFIX/../
grep -ir "${GITHUB_ACTOR}" gfortran-darwin-${arch}-${type}/ || true
tar -czf gfortran-darwin-${arch}-${type}.tar.gz gfortran-darwin-${arch}-${type}
popd
mv $CONDA_PREFIX/../gfortran-darwin-${arch}-${type}.tar.gz .



