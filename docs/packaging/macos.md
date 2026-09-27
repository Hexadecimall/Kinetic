# macOS packaging

`Kinetic.app` is the canonical product. It contains the GUI executable, the matching `kinetic`
command-line client at `Contents/Resources/bin/kinetic`, and the first-party C/C++ Support plugin
at `Contents/PlugIns/libkineticCppSupport.dylib`. The plugin, CLI, and app are signed in that
order after the bundle is assembled; a changed plugin cannot leave a stale bundle signature.
The plugin's Mach-O install name is `@rpath/libkineticCppSupport.dylib`, never an absolute build
path. The separate public plugin release strips build-only symbols and is re-signed before upload.

The installer creates a symlink to that embedded CLI rather than copying it, ensuring the app and
CLI always share a version. The default user installation uses:

- Application: `$HOME/Applications/Kinetic.app`
- CLI link: `$HOME/.local/bin/kinetic`

Homebrew, MacPorts, and system installations choose their own managed prefixes. Release packaging
produces a DMG, a compressed archive, and a MacPorts Portfile generated from that archive's exact
version, hashes, and size. Signing and notarization are enabled only when explicit release
credentials are supplied; developer builds remain ad hoc and local.

Bundle identifier: `top.frameworksdev.kinetic`

`VERSION` is the release source of truth. Packaging refuses inconsistent version metadata, runs the
test suite and public-source audit, and names archives with the embedded CLI version.

MacPorts installs the canonical bundle in its application directory and links `${prefix}/bin/kinetic`
to `Kinetic.app/Contents/Resources/bin/kinetic`, preserving the app/CLI version lockstep. See
[`packaging/macports/README.md`](../../packaging/macports/README.md) for generation and publication.
