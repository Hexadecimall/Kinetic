# C/C++ Support

First-party native plugin `kinetic.cpp-support`, bundled inside `Kinetic.app/Contents/PlugIns`.
It uses the public plugin ABI: there is no private syntax, navigation, or diagnostics hook.

The plugin provides C/C++ syntax tokens for `.c`, `.h`, `.cc`, `.cpp`, `.cxx`, `.hpp`, `.hh`, and
`.hxx`; a clangd language-server session for live diagnostics and Go to Definition; an explicit
clang-format formatter; and Switch Header / Source. Go to Definition is Command-Option-B and
Switch Header / Source is Command-Option-H. The same actions appear in the Plugins panel.
Format Document appears in File for matching extensions when clang-format is available. The
formatter honors a nearby `.clang-format` file through clang-format's normal discovery.

Kinetic uses an existing `clangd` on `PATH` and the active Xcode toolchain's `clang-format`.
Neither is downloaded by the plugin. If clangd is unavailable, syntax highlighting remains
active, while diagnostics and navigation are unavailable; the Plugins panel shows that status.
Header/source switching searches sibling files with a matching stem. A project-local
`compile_commands.json` is used by clangd through its normal discovery rules.

The user can disable the bundle with `disabledFiles = ["libkineticCppSupport.dylib"]` under
`[plugins]` in `~/.kinetic/config.toml`, or disable all native plugins with `enabled = false`.
The bundled plugin is first-party and marked Official in the editor only when loaded from the
signed app bundle. It has not been published to the GitHub plugin catalog; that catalog requires
an immutable public Release asset, checksum, and matching publisher policy entry.

Build and test through `./scripts/test`. The Rust plugin crate has isolated unit tests; the
native integration test starts an actual clangd and checks diagnostics and definition navigation.
