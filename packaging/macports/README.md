# MacPorts packaging

Kinetic ships a generated binary Portfile for Apple Silicon macOS 15 and newer. The port installs
the release `Kinetic.app` into MacPorts' application directory and creates `${prefix}/bin/kinetic`
as a symlink to the CLI embedded in that same application bundle.

The checked-in `Portfile.in` is the source template. Do not enter release hashes by hand. Generate
a release-ready `dist/macports/Portfile` from the versioned ZIP with:

```sh
./scripts/package
```

The packaging gate renders the repository version, RIPEMD-160 digest, SHA-256 digest, and archive
size into the Portfile. When the `port` command is available, it also runs MacPorts' strict lint
against the generated file.

To regenerate only the Portfile after an archive already exists, run:

```sh
./scripts/generate-macports
```

After publishing the matching GitHub release tag and archive, the generated Portfile can be tested
as a local port before submission to the official ports tree. Its download URL expects a `vX.Y.Z`
tag and `Kinetic-X.Y.Z-macos-arm64.zip` release asset.
