<p align="center">
  <img src="assets/branding/kinetic-lockup-dark.svg" alt="Kinetic" width="420">
</p>

<p align="center">
  A macOS code editor with a custom interface and Rust/C++ plugin support.
</p>

> [!IMPORTANT]
> Kinetic `0.31.2` is an early functional preview. Editing, retained multi-document tabs, persisted
> recent projects, mouse selection, undo/redo, basic syntax highlighting, auto-indentation,
> matching delimiters, custom context menus, in-file and project search, the activity bar, GitHub
> account sign-in, native plugin host, hidden-file browsing, project file and folder creation,
> file-name search, configurable indentation, opening, saving, scrolling, shortcuts, and the macOS shell work, but production editor features
> are still under active development.

The bundled Official [C/C++ Support](plugins/official/cppSupport/README.md) plugin adds C/C++ syntax,
clangd diagnostics, completion, Go to Definition, clang-format, and header/source switching. The
0.4.0 bundled build is not yet published in the public catalog. It uses the
same public plugin API available to third-party native plugins. Its first signed arm64 asset is
published in the GitHub-backed catalog as Official. The Plugins page browses that catalog and
manages third-party native plugins. C/C++ Support is included in the app; its source and public API
remain the same as separately published native plugins.

Command-Shift-P opens the Command Palette, including Clone Repository and three color presets.
Drag the Explorer panel's right edge to resize it. Layout and theme choices persist in
`~/.kinetic/layout.toml` and `~/.kinetic/theme.toml`.

## Direction

Kinetic supports TOML configuration for plugins, indentation, and completion. Layered configuration
and Lua automation are not implemented. Rust and C++ plugins use a versioned C ABI, documented in
[`docs/plugin-api/README.md`](docs/plugin-api/README.md).
The GitHub-backed plugin registry and publication process are documented in
[`registry/README.md`](registry/README.md).
GitHub sign-in and its current permission boundary are documented in
[`docs/architecture/accounts.md`](docs/architecture/accounts.md).

The first platform is Apple Silicon macOS 15 or newer. Linux and Intel macOS support are planned
after the macOS experience is mature.

## Install

Apple Silicon, macOS 15 or newer:

```sh
brew install --cask Hexadecimall/Kinetic/kinetic
```

The preview is not notarized. If macOS blocks launch, review the app in System Settings →
Privacy & Security. The cask installs the app and `kinetic` CLI, without LLVM or language servers.
Updates use `brew upgrade --cask Hexadecimall/Kinetic/kinetic`.

The source installer (`./scripts/install`) signs the installed copy locally and verifies its
signature before linking the CLI. To install an already extracted release without building:

```sh
./scripts/install --app /path/to/Kinetic.app
```

The incoming bundle must have a valid signature. Local ad-hoc signing does not provide Apple
notarization, remove quarantine, or change Gatekeeper settings. Installation defaults to
`~/Applications` and `~/.local/bin`; override with `KINETIC_APP_DIR` and `KINETIC_BIN_DIR`.

## Build

Requirements:

- Apple Silicon Mac running macOS 15 or newer
- Xcode command-line tools with Metal support
- CMake 3.28 or newer
- A Rust toolchain with Cargo
- Python 3

Language tools are not bundled. Opening a C-family file checks installed tools and offers a
private download for missing tools; see [`lib/llvm/README.md`](lib/llvm/README.md).

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
