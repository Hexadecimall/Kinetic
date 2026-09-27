# macOS release inputs

This directory is reserved for signing entitlements, icon catalogs, DMG presentation assets, and
notarization configuration. Developer builds do not require credentials. Release credentials must
come from the environment or system keychain and must never be committed.

Run `scripts/package` for the complete release gate. It validates `main.feature.patch` metadata,
audits public sources, executes tests, builds the release app and embedded CLI, then emits versioned
DMG and ZIP artifacts with SHA-256 checksums.
The app bundle contains no C/C++ Support dylib. That Official plugin is built and published
separately; users install it from the plugin catalog.
It also renders `dist/macports/Portfile` from the ZIP's version, hashes, and byte size.
