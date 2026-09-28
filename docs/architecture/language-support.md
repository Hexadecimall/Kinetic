# Language support rollout

## Implemented

C/C++ Support also routes Objective-C and Objective-C++ documents through clangd. It provides
syntax highlighting, completion, diagnostics, same-file quick fixes, definition navigation,
formatting, and header/source switching. The app's LLVM tool bundle includes clangd,
clang-format, their non-system runtime dependencies, resource headers, and licenses.

Developer builds may use a local LLVM that targets newer macOS, with warnings. Such a bundle
must not be published as macOS-15-compatible. Release packaging rejects that mismatch.

## Requested, not implemented yet

Separate language plugins are still needed for Rust, Zig, JavaScript/TypeScript, assembly,
Swift, Python, TOML, JSON, Java, Kotlin, shell scripts, and CMake/Make. Additional essentials
need an explicit supported-language list. Existing basic editor syntax colors do not constitute
an implemented language plugin.

Distribution must distinguish app-bundled tools from server/runtime downloads attached to
individual plugins. Server archives require pinned versions, verified checksums, redistribution
notices, compatible architectures and OS versions, and an explicit install action. Installing
a plugin must not silently install a system-wide runtime or toolchain.

## Capability acceptance

Each plugin needs tests with its real server for completion, diagnostics, definition navigation,
formatting, and supported fixes, plus language-specific behavior. Tests must cover opening a
project, editing and saving a document, switching documents, restarting the server, and missing
dependencies. Formatters may be separate from the language server.

Capabilities must be negotiated with the server. Unsupported operations stay disabled and are
documented; an adapter does not manufacture parity with clangd. Header/source switching is a
C-family operation, not a requirement for unrelated languages. Compiler/SDK/project build
requirements remain distinct from editor language services.
