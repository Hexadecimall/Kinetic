# macOS release inputs

This directory is reserved for signing entitlements, icon catalogs, DMG presentation assets, and
notarization configuration. Developer builds do not require credentials. Release credentials must
come from the environment or system keychain and must never be committed.

Run `scripts/package` for the complete release gate. It validates `main.feature.patch` metadata,
audits public sources, executes tests, builds the release app and embedded CLI, then emits versioned
DMG and ZIP artifacts with SHA-256 checksums.
The bundled C/C++ Support dylib is copied into `Contents/PlugIns` and signed before the outer app.
It also renders `dist/macports/Portfile` from the ZIP's version, hashes, and byte size.
