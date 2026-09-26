# Versioning and change discipline

Kinetic versions use `main.feature.patch`:

- `main` increments for a new stable generation or an intentionally incompatible product/API
  boundary.
- `feature` increments for user-visible additions or meaningful updates. `patch` resets to zero.
- `patch` increments for compatible bug fixes, polish, documentation corrections, and packaging
  repairs that do not add a feature.

`feature` and `patch` each run from 0 through 99. A patch bump from `0.9.99` becomes `0.10.0`;
either bump beyond `0.99.99` becomes `1.0.0`. Explicit versions outside these bounds are rejected.

`VERSION` is the release source of truth. CMake reads it directly; Rust package metadata is checked
against it. Run `./scripts/version check` before committing and packaging.

```sh
./scripts/version show
./scripts/version bump feature
./scripts/version bump patch
./scripts/version next patch 0.99.99
./scripts/version set 1.0.0
```

Every meaningful change must update the relevant documentation, tests, and `CHANGELOG.md` entry in
the same commit. Public changes must pass `./scripts/audit-public`. Release packaging runs the
version check, public audit, and test suite automatically before producing artifacts.
Package-manager metadata is generated from the same versioned archive, never maintained as a
second version source.

Configuration and plugin API changes must document their default, accepted values, runtime effect,
and compatibility behavior. Defaults are never treated as permanent limits: interface metrics,
themes, shortcuts, animations, scrolling, editor behavior, dialogs, tooling, and language support
are designed to be replaceable through settings or supported APIs.
