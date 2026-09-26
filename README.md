<p align="center">
  <img src="assets/branding/kinetic-lockup-dark.svg" alt="Kinetic" width="420">
</p>

<p align="center">
  A deeply customizable, GPU-rendered code editor with a polished ready-to-go experience.
</p>

> [!IMPORTANT]
> Kinetic `0.8.2` is an early functional preview. Editing, retained multi-document tabs, persisted
> recent projects, mouse selection, undo/redo, custom context menus, the activity bar, file
> browsing, opening, saving, scrolling, shortcuts, and the macOS application shell work, but
> production editor features are still under active development.

## Direction

Kinetic combines a fast custom interface with first-class project tooling and an editor that
works well before any configuration is written. TOML handles declarative settings, Lua handles
dynamic configuration and automation, and a native plugin API will support Rust and C++.

The first platform is Apple Silicon macOS 15 or newer. Linux and Intel macOS support are planned
after the macOS experience is mature.

## Build

Requirements:

- Apple Silicon Mac running macOS 15 or newer
- Xcode command-line tools with Metal support
- CMake 3.28 or newer
- A Rust toolchain with Cargo

```sh
./scripts/bootstrap
./scripts/build
./scripts/run
```

Useful entry points:

```sh
./scripts/test
./scripts/format
./scripts/lint
./scripts/package
./scripts/generate-macports
./scripts/install
./scripts/version check
./scripts/audit-public
```

Brand assets are source-controlled. Regenerate the macOS icon after changing its SVG source with
`./scripts/generate-icons`.

Build products stay under `build/`; distributable archives and the generated MacPorts Portfile stay
under `dist/`.

## Architecture

- C++, Objective-C++, AppKit, and Metal own the application shell, renderer, input, and UI.
- Rust owns the editor model, workspace state, configuration, language tooling, and plugin host.
- A narrow versioned C ABI connects both sides.
- Third-party source is pinned under `lib/` with provenance and license information.

See [`docs/architecture/overview.md`](docs/architecture/overview.md) for the boundary rules.
Versioning and change requirements are documented in
[`docs/versioning.md`](docs/versioning.md), with release notes in [`CHANGELOG.md`](CHANGELOG.md).

## License

Kinetic is licensed under the [Apache License 2.0](LICENSE).
