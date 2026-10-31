# macOS packaging

The app does not contain clangd, clang-format, or LLVM. Language tools are detected locally or
downloaded with confirmation into `~/.kinetic/tools`. See [language tools](../../lib/llvm/README.md).
They do not replace project compilers, SDKs, or build-system dependencies.

`Kinetic.app` is the canonical product. It contains the GUI executable, the matching `kinetic`
command-line client at `Contents/Resources/bin/kinetic`, and Official C/C++ Support at
`Contents/PlugIns/libkineticCppSupport.dylib`. The CLI, plugin, and app are signed after
bundle assembly. The plugin's Mach-O install name is `@rpath/libkineticCppSupport.dylib`, never
an absolute build path. Its public release strips build-only symbols and is re-signed before upload.

The installer creates a symlink to that embedded CLI rather than copying it, ensuring the app and
CLI always share a version. The default user installation uses:

- Application: `$HOME/Applications/Kinetic.app`
- CLI link: `$HOME/.local/bin/kinetic`

Homebrew, MacPorts, and system installations choose their own managed prefixes. Release packaging
produces a DMG, a compressed archive, and a MacPorts Portfile generated from that archive's exact
version, hashes, and size. Signing and notarization are enabled only when explicit release
credentials are supplied; developer builds remain ad hoc and local.

Bundle identifier: `org.kinetic.app`. Installers also recognize the legacy
`top.frameworksdev.kinetic` identifier for migration. Settings and plugins retain their
existing `~/.kinetic` locations. GitHub sessions migrate from the legacy Keychain service
after a successful save to `org.kinetic.app.github`.
The updater shipped before 0.36.1 recognizes only the legacy identifier. A source installation
or the 0.36.1 package client performs the one-time transition; subsequent updates accept both
identifiers while new app bundles use `org.kinetic.app`.

`VERSION` is the release source of truth. Packaging refuses inconsistent version metadata, runs the
test suite and public-source audit, and names archives with the embedded CLI version.

MacPorts installs the canonical bundle in its application directory and links `${prefix}/bin/kinetic`
to `Kinetic.app/Contents/Resources/bin/kinetic`, preserving the app/CLI version lockstep. See
[`packaging/macports/README.md`](../../packaging/macports/README.md) for generation and publication.

The embedded CLI supports `kinetic app check`, `install`, `update`, and `uninstall`, also exposed
in the dedicated Settings page. This user-scoped manager targets `$HOME/Applications/Kinetic.app`;
it does not directly replace a Homebrew, MacPorts, or system-managed installation. Homebrew
ownership is detected from the resolved Cellar bundle and its installation receipt, including
when launched through an application symlink. Checks read the Kinetic formula's version, not
the GitHub binary release. Updates refresh Homebrew metadata and run
`brew upgrade --formula hexadecimall/kinetic/kinetic`; Homebrew retains control of building,
signing, links, and installed files. Automatic cleanup is disabled during this operation.
Uninstall directs Homebrew installations to `brew uninstall hexadecimall/kinetic/kinetic`.
Standalone install and update use a
stable, immutable GitHub release asset named `Kinetic-VERSION-macos-arm64.zip`, verify GitHub's
SHA-256 digest and asset size, then verify the extracted bundle identifier, version, bundled CLI,
and code signature before replacing the user installation. The previous app is retained in Trash
or beside the replacement if Trash is unavailable. Uninstall moves the app to Trash and preserves
`~/.kinetic/` settings and plugins. Until an application release with that asset exists,
`kinetic app check` reports that no release is published.
