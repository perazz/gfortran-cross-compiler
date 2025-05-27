#!/usr/bin/env bash
set -euxo pipefail

########################################################################
# 0.  Enable micromamba shell support so that `micromamba activate` works
########################################################################
eval "$(micromamba shell hook -s bash)"

########################################################################
# 1.  Read version / target-arch / build-arch
#     * They can be passed as positional args
#     * or come from environment variables set by the workflow
########################################################################
ver=${1:-${GFORTRAN_VERSION:-11.3.0}}   # GCC version to install
arch=${2:-${TARGET_ARCH:-x86_64}}       # target architecture
build=${3:-${BUILD_ARCH:-$arch}}        # host (build) architecture

########################################################################
# 2.  Map arches to conda subdirs and Darwin kernel versions
########################################################################
if [[ $arch == x86_64 ]]; then
  export CONDA_HOST_SUBDIR="osx-64"
  kern_ver=13.4.0
else
  export CONDA_HOST_SUBDIR="osx-arm64"
  kern_ver=20.0.0
fi

if [[ $build == x86_64 ]]; then
  export CONDA_BUILD_SUBDIR="osx-64"
else
  export CONDA_BUILD_SUBDIR="osx-arm64"
fi

# native == host == target ; cross == host != target
type=$([[ $arch == "$build" ]] && echo native || echo cross)

########################################################################
# 3.  Create a new environment and install the compiler
########################################################################
export CONDA_SUBDIR=$CONDA_BUILD_SUBDIR
micromamba create -n gfortran-darwin-"$arch"-"$type" \
  gfortran_impl_"$CONDA_SUBDIR"="$ver" \
  libgfortran-devel_"$CONDA_SUBDIR"="$ver" --yes

export CONDA_SUBDIR=$CONDA_HOST_SUBDIR
micromamba install -n gfortran-darwin-"$arch"-"$type" \
  libgfortran5="$ver" --yes

micromamba activate gfortran-darwin-"$arch"-"$type"

########################################################################
# 4.  Strip unneeded files to keep the package small
########################################################################
rm -rf "$CONDA_PREFIX"/lib/{libc++*,*.a,pkgconfig,clang}
rm -rf "$CONDA_PREFIX"/{include,conda-meta,bin/iconv}

for f in "$CONDA_PREFIX"/lib/{libgmp.dylib,libgmpxx.dylib,libisl.dylib,libiconv.dylib,libmpfr.dylib,libz.dylib,libcharset.dylib,libmpc.dylib}; do
  install_name_tool -delete_rpath "$CONDA_PREFIX"/lib "$f" || true
  install_name_tool -delete_rpath "$CONDA_PREFIX"/lib "$f" || true
  rm "$f"
done

rm "$CONDA_PREFIX"/lib/libiomp5.dylib

########################################################################
# 5.  For cross builds, move target runtime libs into GCC's tree
########################################################################
if [[ $type == cross ]]; then
  dest="$CONDA_PREFIX"/lib/gcc/"$arch"-apple-darwin"$kern_ver"/"$ver"
  mkdir -p "$dest"
  mv "$CONDA_PREFIX"/lib/{libgfortran*,libgomp*,libomp*,libgcc_s*} "$dest"
fi

########################################################################
# 6.  Point GCC's linker stub at the system linker
########################################################################
execdir="$CONDA_PREFIX"/libexec/gcc/"$arch"-apple-darwin"$kern_ver"/"$ver"
mkdir -p "$execdir"
ln -sf /usr/bin/ld "$execdir"/ld

########################################################################
# 7.  Delete the absolute RPATH baked into libgfortran.spec (if a file)
########################################################################
specfile="$CONDA_PREFIX"/lib/gcc/"$arch"-apple-darwin"$kern_ver"/"$ver"/libgfortran.spec
if [[ -f $specfile && ! -L $specfile ]]; then
  sed -i '' "s#-rpath $CONDA_PREFIX/lib##g" "$specfile"
fi

########################################################################
# 8.  Unwrap cc1 if the real binary exists; leave as-is in cross case
########################################################################
if [[ -f "$execdir"/cc1.bin ]]; then
  rm -f "$execdir"/cc1          # delete the wrapper script
  mv     "$execdir"/cc1.bin "$execdir"/cc1
fi

########################################################################
# 9.  Package the environment into a tarball
########################################################################
pushd "$CONDA_PREFIX/.." >/dev/null
grep -ir "$GITHUB_ACTOR" gfortran-darwin-"$arch"-"$type"/ || true
tar -czf gfortran-darwin-"$arch"-"$type".tar.gz \
  gfortran-darwin-"$arch"-"$type"
popd >/dev/null

mv "$CONDA_PREFIX"/../gfortran-darwin-"$arch"-"$type".tar.gz .
echo "Created gfortran-darwin-$arch-$type.tar.gz"
