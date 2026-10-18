# Homebrew packaging

## Source formula

`kineticFormula.rb.in` is the supported installation path. It builds Kinetic locally, installs
the app in the Homebrew Cellar, and links the embedded CLI. It requires an existing Cargo toolchain
instead of depending on Homebrew Rust, whose dependency tree includes LLVM. CMake is a build-only
dependency; Apple Command Line Tools supply the native compiler. No language tools are bundled.

Generate the formula from a published immutable source commit and its downloaded archive:

```sh
python3 scripts/generateHomebrewFormula.py --archive source.tar.gz --commit FULL_COMMIT_SHA
```

Publish `dist/homebrew/Formula/kinetic.rb` as `Formula/kinetic.rb` in the tap. Install with
`brew install --formula Hexadecimall/Kinetic/kinetic`. No bottle is published, so installation
builds from source. The source archive checksum and version are taken from the archive, not a
downloaded app. The formula verifies the installed bundle signature and rejects a tools directory.

## Legacy binary cask

The binary cask is disabled in the public tap. Local re-signing did not resolve its Gatekeeper
rejection. The template remains available for future notarized binary distribution.

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
