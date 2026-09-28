<p align="center">
  <img src="assets/branding/kinetic-lockup-dark.svg" alt="Kinetic" width="420">
</p>

<p align="center">
  A deeply customizable, GPU-rendered code editor with a polished ready-to-go experience.
</p>

> [!IMPORTANT]
> Kinetic `0.27.1` is an early functional preview. Editing, retained multi-document tabs, persisted
> recent projects, mouse selection, undo/redo, basic syntax highlighting, auto-indentation,
> matching delimiters, custom context menus, in-file and project search, the activity bar, GitHub
> account sign-in, native plugin host, hidden-file browsing, project file and folder creation,
> file-name search, configurable indentation, opening, saving, scrolling, shortcuts, and the macOS shell work, but production editor features
> are still under active development.

The bundled Official [C/C++ Support](plugins/official/cppSupport/README.md) plugin adds C/C++ syntax,
clangd diagnostics, completion, Go to Definition, clang-format, and header/source switching. The
0.2.0 completion build awaits its immutable release before it appears in the public catalog. It uses the
same public plugin API available to third-party native plugins. Its first signed arm64 asset is
published in the GitHub-backed catalog as Official. The Plugins page browses that catalog and
manages third-party native plugins. C/C++ Support is included in the app; its source and public API
remain the same as separately published native plugins.

Command-Shift-P opens the Command Palette, including Clone Repository and three color presets.
Drag the Explorer panel's right edge to resize it. Layout and theme choices persist in
`~/.kinetic/layout.toml` and `~/.kinetic/theme.toml`.

## Direction

Kinetic combines a fast custom interface with first-class project tooling and an editor that
works well before any configuration is written. TOML handles declarative settings, Lua handles
dynamic configuration and automation. A first native plugin API now supports Rust and C++ through
a versioned C ABI; its current surface is documented in [`docs/plugin-api/README.md`](docs/plugin-api/README.md).
The GitHub-backed plugin registry and publication process are documented in
[`registry/README.md`](registry/README.md).
GitHub sign-in and its current permission boundary are documented in
[`docs/architecture/accounts.md`](docs/architecture/accounts.md).

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
build/debug/Kinetic.app/Contents/Resources/bin/kinetic plugins list
build/debug/Kinetic.app/Contents/Resources/bin/kinetic app check
```

Brand assets are source-controlled. Regenerate the macOS icon after changing its SVG source with
`./scripts/generate-icons`.

Build products stay under `build/`; distributable archives and the generated MacPorts Portfile stay
under `dist/`.

## Architecture

- C++, Objective-C++, AppKit, and Metal own the application shell, renderer, input, and UI.
- C++ hosts native plugin callbacks and the custom editor surface. Rust owns document state and
  plugin contribution metadata; moving more editor-model responsibilities to Rust remains
  architectural direction.
- A narrow versioned C ABI connects both sides.
- Third-party source is pinned under `lib/` with provenance and license information.

See [`docs/architecture/overview.md`](docs/architecture/overview.md) for the boundary rules.
Versioning and change requirements are documented in
[`docs/versioning.md`](docs/versioning.md), with release notes in [`CHANGELOG.md`](CHANGELOG.md).

## License

Kinetic is licensed under the [Apache License 2.0](LICENSE).
