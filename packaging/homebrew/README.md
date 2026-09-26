# Homebrew packaging

Kinetic will ship through a cask after signed and notarized release artifacts exist. The cask should
install `Kinetic.app` and expose `Contents/Resources/bin/kinetic` as the `kinetic` command. It must
use the release checksum from `dist/SHA256SUMS` and must not rebuild the application during install.

Formula metadata must match the repository `VERSION` file and the version reported by the embedded
CLI. A feature release resets the patch component to zero.

MacPorts support is maintained separately under `packaging/macports/`; both package-manager paths
must install the same release app bundle and expose its embedded CLI rather than copying a second
binary.
