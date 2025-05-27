# gfortran-darwin cross-compiler bundles

This GitHub Action assembles relocatable tar-balls that contain both x86-64
and arm64 flavours of GCC/gfortran **14.x** built from conda-forge packages.

Forward-compatibility: bump the `gcc:` matrix in
`.github/workflows/build-gfortran.yml` and push -- that’s it.
