# LLVM language tools

Kinetic bundles clangd, clang-format, Clang resource headers, and required non-system dynamic
libraries in `Contents/Resources/tools/llvm`. Source dependencies remain external to the checkout;
the packaging step copies their license and notice files into the bundle's `licenses/` directory.

LLVM is licensed under Apache-2.0 with LLVM exceptions. See the
[upstream license](https://github.com/llvm/llvm-project/blob/main/llvm/LICENSE.TXT).
Any additional runtime libraries retain their own licenses.

Configure `KINETIC_LLVM_ROOT` with a redistributable LLVM installation containing both tools,
resource headers, and license files. `scripts/bundleClangTools.py` recursively copies dependencies,
rewrites loader paths, removes host rpaths, signs the copied binaries, and checks arm64 support.
Release packaging rejects any binary requiring a newer macOS than Kinetic's deployment target.
Debug builds allow a newer local toolchain with an explicit warning; these are not release artifacts.

The plugin prefers the app's tools. `KINETIC_CLANGD` and `KINETIC_CLANG_FORMAT` explicitly override
the executables without invoking a shell. Outside an app bundle, tool lookup falls back to PATH.
Project compilers, SDKs, build systems, and compile databases are not bundled by this component.
