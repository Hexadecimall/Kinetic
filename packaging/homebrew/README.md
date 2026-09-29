# Homebrew packaging

`kinetic.rb.in` defines the Apple Silicon macOS 15+ cask. `scripts/package` generates
`dist/homebrew/Casks/kinetic.rb` from the exact release ZIP with its SHA-256 checksum. The generator
checks the app version, bundle identifier, embedded CLI, and absence of bundled LLVM tools.

The cask installs `Kinetic.app` and links its embedded CLI as `kinetic`; it does not build source or
install language servers. Ordinary uninstall preserves `~/.kinetic/` settings and downloaded tools.
Homebrew-managed app upgrades use `brew upgrade --cask Hexadecimall/Kinetic/kinetic`.

Before installation, Homebrew verifies the downloaded bundle, ad-hoc signs the plugin, CLI,
and app locally in that order, then verifies the completed signature. It verifies the app again
at its installed location. Failed signing or verification aborts installation. This does not
remove quarantine or provide Apple notarization. Existing installations can run
`brew reinstall --cask Hexadecimall/Kinetic/kinetic` to apply the signing steps.

Publication requires the matching ZIP at the versioned GitHub release URL and the generated cask
in `Hexadecimall/homebrew-Kinetic`, under `Casks/kinetic.rb`. After publication:

```sh
brew install --cask Hexadecimall/Kinetic/kinetic
```

The current packaging script produces ad-hoc-signed previews and explicitly marks the cask as
unnotarized. It does not remove quarantine attributes or change Gatekeeper settings. A generated
cask is not a published tap; verify the public release URL and installation before announcing it.

Formula metadata must match the repository `VERSION` file and the version reported by the embedded
CLI. A feature release resets the patch component to zero.

MacPorts support is maintained separately under `packaging/macports/`; both package-manager paths
must install the same release app bundle and expose its embedded CLI rather than copying a second
binary.
