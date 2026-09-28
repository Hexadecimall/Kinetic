# LLVM language tools

Kinetic ships without LLVM, clangd, or clang-format. Opening a C-family document checks local tools
and offers a Yes/No prompt for missing executables. No downloads occur before Yes.

LLVM is licensed under Apache-2.0 with LLVM exceptions. See the
[upstream license](https://github.com/llvm/llvm-project/blob/main/llvm/LICENSE.TXT).
Any additional runtime libraries retain their own licenses.

Pinned standalone packages:

- clangd 23.1.0 from the official clangd GitHub releases: 100,060,151 bytes, including resource
  headers and the LLVM license. SHA-256: `1082e6638223b785ca2daf0939f13afcd0bb95c84ee9a4bbaff4745365159253`.
- clang-format 23.1.1 from the PyPI clang-format project (unofficial binary packaging): 1,552,401
  bytes. Only the native executable and license notices are installed; Python and pip are not
  required. SHA-256: `d64a1788759c4cbc08a0aca21dd2bd38605c0758543aa15b8c0636508f0ebae7`.

The package client checks HTTPS, bounded download size, pinned SHA-256, and executable startup.
Downloads are staged under `~/.kinetic/tools` and renamed into place after validation. Existing
unusable installations are preserved, not overwritten. No system package manager is invoked.

`KINETIC_CLANGD` and `KINETIC_CLANG_FORMAT` select explicit executable candidates. Private tools,
PATH, Homebrew, and MacPorts locations are searched next. `KINETIC_TOOLS_DIR` can select an
absolute private directory; the default is `~/.kinetic/tools`. CLI operations are `kinetic tools
status` and `kinetic tools install clangd` / `kinetic tools install clang-format`.
`KINETIC_TOOL_SEARCH_PATH` optionally replaces PATH and package-manager discovery with a
colon-separated directory list. An empty list restricts discovery to explicit overrides and
private installations.
Project compilers, SDKs, build systems, and compile databases are not bundled by this component.
