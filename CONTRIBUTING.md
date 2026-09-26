# Contributing to Kinetic

Kinetic is early in development. Focused issues and narrowly scoped pull requests are welcome.

## Before changing code

1. Search existing issues and pull requests.
2. Open an issue before beginning a large architectural or user-facing change.
3. Keep each change focused on one concern.
4. Do not commit generated build output, credentials, local paths, or machine-specific settings.

## Required checks

```sh
./scripts/format --check
./scripts/lint
./scripts/test
./scripts/version check
./scripts/audit-public
```

Changes to behavior require tests. Changes to public interfaces require documentation. Changes to
vendored dependencies require updated provenance, license files, and third-party notices.

## Source conventions

- C++ and Objective-C++ use the repository `.clang-format` configuration.
- Rust uses `rustfmt.toml` and must pass Clippy without warnings.
- Hot input, layout, text, and rendering paths must not cross the plugin ABI unnecessarily.
- Public APIs use stable, versioned handles rather than exposing Rust or C++ object layouts.
- Platform-specific behavior stays behind a platform boundary.
- Kinetic-owned identifiers and filenames use camelCase unless a language, platform, or external
  ABI requires another spelling.
- Every meaningful change updates its tests, relevant docs, and `CHANGELOG.md` in the same commit.
- Versions follow `main.feature.patch`; use `./scripts/version bump feature|patch` rather than
  editing scattered metadata.

By submitting a contribution, its author agrees to license it under Apache-2.0.
