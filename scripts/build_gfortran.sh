#!/usr/bin/env bash
set -euo pipefail

#######################################################################
# 0.  Enable micromamba shell support so that `micromamba activate` works
#######################################################################
eval "$(micromamba shell hook -s bash)"

#######################################################################
# 1.  Read inputs
#######################################################################
ver=${1:-${GFORTRAN_VERSION:-11.3.0}}   # GCC version to install
arch=${2:-${TARGET_ARCH:-x86_64}}       # target architecture
build=${3:-${BUILD_ARCH:-$arch}}        # host (build) architecture

#######################################################################
# 2.  Map arches to conda sub-dirs and Darwin kernel versions
#######################################################################
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

type=$([[ $arch == "$build" ]] && echo native || echo cross)

#######################################################################
# 3.  Create a fresh environment and install the compiler
#     * libgfortran-devel brings the static archives we want
#######################################################################
export CONDA_SUBDIR=$CONDA_BUILD_SUBDIR
micromamba create -n gfortran-darwin-"$arch"-"$type" \
  gfortran_impl_"$CONDA_BUILD_SUBDIR"="$ver" \
  libgfortran-devel_"$CONDA_BUILD_SUBDIR"="$ver" \
  isl --yes             
  
# ── runtime for the HOST side (needed to run gcc itself)
export CONDA_SUBDIR=$CONDA_HOST_SUBDIR
micromamba install -n gfortran-darwin-"$arch"-"$type" \
  libgfortran5="$ver" \
  isl --yes             

micromamba activate gfortran-darwin-"$arch"-"$type"
PREFIX="$CONDA_PREFIX"
  
# ────────────────────────────────────────────────────────────────
# 4.  Trim unneeded files and arrange runtime libs
#     (same spirit as the original helper script)
# ────────────────────────────────────────────────────────────────

# 4-a) drop C++ headers, static archives, clang bits we never ship
rm -rf "$PREFIX"/lib/{libc++*,*.a,pkgconfig,clang}
rm -rf "$PREFIX"/{include,conda-meta,bin/iconv}

# 4-b) clean rpaths inside *runtime* dylibs so they are fully reloc-friendly
#      NOTE: we **keep** libisl, removing only the rpath entries.
for f in "$PREFIX"/lib/{libgmp.dylib,libgmpxx.dylib,libiconv.dylib,libmpfr.dylib,libz.dylib,libcharset.dylib,libmpc.dylib,libisl.dylib}; do
    install_name_tool -delete_rpath "$PREFIX/lib" "$f" 2>/dev/null || true
done

# 4-c) remove Intel OpenMP (unused) to save a bit of space
rm -f "$PREFIX"/lib/libiomp5.dylib

# 4-d) when building a *cross* tool-chain, place the runtime libraries
#      next to libgcc so the linker finds them automatically
if [[ "$type" == "cross" ]]; then
    mv "$PREFIX"/lib/{libgfortran*,libgomp*,libomp*,libgcc_s*} \
       "$PREFIX"/lib/gcc/${arch}-apple-darwin${kern_ver}/${ver}
fi

# 4-e)  GCC front-ends look for libs via @loader_path/../../../../lib
#       which resolves to  <prefix>/bin/libexec/lib
#       Create that shim so libisl is always found.
mkdir -p "$PREFIX"/bin/libexec
ln -sf ../../lib "$PREFIX"/bin/libexec/lib  

#######################################################################
# 5.  Delete *all* shared libraries and other clutter
#######################################################################
find "$PREFIX"/lib -maxdepth 1 -name '*.dylib' -exec rm -f {} +

rm -rf "$PREFIX"/{include,conda-meta,bin/iconv}

# Keep static libgfortran / libquadmath / libgcc – we need them later
# Everything else under lib/*.a can go after we move the keepers.
rm -rf "$PREFIX"/lib/{pkgconfig,clang}

#######################################################################
# 6.  For cross builds, move target-side static libs into GCC’s tree
#######################################################################
if [[ $type == cross ]]; then
  dest="$PREFIX"/lib/gcc/"$arch"-apple-darwin"$kern_ver"/"$ver"
  mkdir -p "$dest"

  shopt -s nullglob          # empty globs disappear instead of erroring
  for a in "$PREFIX"/lib/libgfortran*.a \
           "$PREFIX"/lib/libquadmath*.a \
           "$PREFIX"/lib/libgcc*.a; do
    mv "$a" "$dest/"
  done
  shopt -u nullglob
fi

# Now delete any remaining *.a that we don’t care about
find "$PREFIX"/lib -maxdepth 1 -name '*.a' -delete

#######################################################################
# 7.  Point GCC’s linker stub at the system linker
#######################################################################
execdir="$PREFIX"/libexec/gcc/"$arch"-apple-darwin"$kern_ver"/"$ver"
mkdir -p "$execdir"
ln -sf /usr/bin/ld "$execdir"/ld

#######################################################################
# 8.  Patch the specs file so every link is static-runtime by default
#######################################################################
specfile="$PREFIX"/lib/gcc/"$arch"-apple-darwin"$kern_ver"/"$ver"/libgfortran.spec
if [[ -f $specfile && ! -L $specfile ]]; then
  # Keep the original for reference
  cp "$specfile" "${specfile}.orig"
  # Append static runtime flags to *link_command:
  sed -i '' -e '/\*link_command:/ s|$| %{!static:-static-libgfortran -static-libquadmath -static-libgcc}|' "$specfile"
fi

#######################################################################
# 9.  Unwrap cc1 if the real binary exists; leave as-is in cross case
#######################################################################
if [[ -f "$execdir"/cc1.bin ]]; then
  rm -f "$execdir"/cc1
  mv     "$execdir"/cc1.bin "$execdir"/cc1
fi

#---------------------------------------------------------------------
# 8½.  Make GCC's @rpath (@loader_path/../../../../lib) resolve
#      Correct place is  <PREFIX>/lib -> we add a symlink in <PREFIX>/bin
#---------------------------------------------------------------------
ln -sf ../lib "$PREFIX/bin/lib"

#######################################################################
# 9.  Pack the environment
#######################################################################
pushd "$PREFIX/.." >/dev/null
tar -czf gfortran-darwin-"$arch"-"$type".tar.gz \
  gfortran-darwin-"$arch"-"$type"
popd >/dev/null

mv "$PREFIX"/../gfortran-darwin-"$arch"-"$type".tar.gz .
echo "Created gfortran-darwin-$arch-$type.tar.gz"
