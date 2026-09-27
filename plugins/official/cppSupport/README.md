# C/C++ Support

First-party native plugin `kinetic.cpp-support`, installed separately from Kinetic.app through the
Official catalog.
It uses the public plugin ABI: there is no private syntax, navigation, or diagnostics hook.

The plugin provides C/C++ syntax tokens for `.c`, `.h`, `.cc`, `.cpp`, `.cxx`, `.hpp`, `.hh`, and
`.hxx`; a clangd language-server session for live diagnostics, completion, and Go to Definition; an explicit
clang-format formatter; and Switch Header / Source. Go to Definition is Command-Option-B and
Switch Header / Source is Command-Option-H. These actions are editor commands, not Plugins-page rows.
Format Document appears in File for matching extensions when clang-format is available. The
formatter honors a nearby `.clang-format` file through clang-format's normal discovery.

Kinetic uses an existing `clangd` on `PATH` and the active Xcode toolchain's `clang-format`.
Neither is downloaded by the plugin. If clangd is unavailable, syntax highlighting remains
active, while diagnostics and navigation are unavailable.
Header/source switching searches sibling files with a matching stem. A project-local
`compile_commands.json` is used by clangd through its normal discovery rules.

The user can disable the installed plugin with `disabledFiles = ["kinetic.cpp-support.dylib"]` under
`[plugins]` in `~/.kinetic/config.toml`, or disable all native plugins with `enabled = false`.
The Official designation comes from the registry's project-owned publisher policy, not a plugin
self-claim. Version 0.1.0 is published as an immutable
[GitHub Release](https://github.com/Hexadecimall/Kinetic/releases/tag/cpp-support-v0.1.0).
Version 0.2.0 adds clangd completion and is prepared for the next immutable release; the catalog
will list it only after that asset is published and its digest is verified. Install, update, or remove it from the Plugins page or
with `kinetic plugins install kinetic.cpp-support`. Native code runs with the user's privileges;
installation or removal takes effect after restarting Kinetic.

Build and test through `./scripts/test`. The Rust plugin crate has isolated unit tests; the
native integration test starts an actual clangd and checks diagnostics, completion, and definition navigation.
