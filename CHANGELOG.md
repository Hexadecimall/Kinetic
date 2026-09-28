# Changelog

All notable Kinetic changes are recorded here. Versions use `main.feature.patch`.

## 0.29.0 - Unreleased

### Added

- Bundle clangd, clang-format, resource headers, runtime libraries, and redistribution notices; prefer those tools over system installations.
- Handle Objective-C and Objective-C++ documents through clangd with the correct language IDs, completion, diagnostics, formatting, and header/source navigation.
- Reject incompatible LLVM binaries when preparing a macOS release; development bundles explicitly warn about newer toolchain requirements.

## 0.28.0

### Improved

- Replaced Settings and Plugins editor pages with rounded, animated overlays that preserve the workspace and Explorer.
- Organized 23 settings into searchable categories, with centered compact steppers, animated switches, and silent successful saves.
- Added Settings controls for themes, font presets, letter spacing, current-line highlighting, diagnostics, tab sizing, and panel motion.
- Persisted numeric editor preferences through Rust with validated loading and atomic writes; retained TOML indentation/completion and theme configuration.

## 0.27.3

### Fixed

- Collapse the empty tab strip and move the Explorer beneath the titlebar when no tabs are open, preserving the strip for documents, Settings, and Plugins.

## 0.27.2

### Fixed

- Keep the Command Palette opaque beneath its search divider, preventing background content from leaking through the separator.

## 0.27.1

### Improved

- Redesigned Midnight and Graphite with complete surface, text, selection, diagnostic, and syntax palettes loaded from bundled TOML files.
- Fixed immediate theme switching for existing editor canvases and input fields, while preserving explicit plugin canvas colors.
- Added user palette overrides in `~/.kinetic/themes/` and contrast validation for both alternate themes.

## 0.27.0

### Added

- Remember window position and size across launches, keeping restored windows visible on the current monitors.
- Bundled Official C/C++ Support 0.2.0 inside Kinetic.app and marked it Included in the plugin browser and bundled CLI.
- Added a searchable Command Palette with Command-Shift-P, a custom Clone Repository flow, and an Explorer panel edge that resizes and persists in `~/.kinetic/layout.toml`.
- Added Kinetic Dark, Midnight, and Graphite color presets selectable from the Command Palette; the choice persists in `~/.kinetic/theme.toml`.

### Fixed

- Gave the Plugins search field enough inset so its text no longer overlaps the search icon.

## 0.26.0

### Added

- Added clangd member completion after `.`, `->`, and `::` without requiring a typed prefix;
  new configurations default to 12 suggestions after one character.
- Added small inline Fix buttons for clangd diagnostics with quick fixes, backed by actual
  `textDocument/codeAction` requests and same-file edit validation.
- Added indentation-unit cursor movement and faint indentation markers/guides, with Settings and
  dotfile controls.

### Fixed

- Diagnostic messages no longer occupy the code line; hovering an underline reveals a compact
  message popover with the Fix action when available.
- C/C++ Support discovers CMake compilation databases in common build directories and restarts
  clangd when the active project changes, avoiding fallback-parser error cascades.

## 0.25.0

### Added

- Added a compact, animated Settings page with Command-Comma access, shared live controls,
  dotfile-backed autocomplete and indentation preferences, and spaces-or-tabs selection.
- Added file-name search in Explorer and custom Open File/Open Folder pickers.
- Connected installable C/C++ Support 0.2.0 to clangd completion, including an actual clangd
  integration test. Its registry update follows publication of the immutable 0.2.0 asset.

### Fixed

- Opening a project no longer creates an Untitled document; closing the last real document keeps
  an empty workspace when a project remains open.
- Backspace removes one indentation unit from leading whitespace.
- Plugin install/update/remove use a dedicated confirmation panel rather than a context menu.
- Suggestion popups fit their contents and omit redundant headings and generic word labels.

## 0.24.0

### Added

- Added Rust-owned document-word autocomplete with a Kinetic-drawn suggestion popup, keyboard
  navigation, and `[autocomplete]` settings in the user dotfile.
- Added an append-only native plugin API for extension-scoped completion providers and live
  autocomplete controls for installed plugins.

### Changed

- C/C++ Support is now built and published as a separate Official plugin, not copied into
  Kinetic.app. It can be installed, updated, and removed through the Plugins page or CLI.

## 0.23.0

### Added

- Added a searchable Discover/Installed plugin page with publisher, Official status, description,
  version, technical details, and honest unrated state. Bundled C/C++ Support is marked Included,
  not presented as a removable core plugin.
- Added Rust-owned CLI and in-app plugin install, update, and removal against the public catalog.
  Downloads are size- and SHA-256-checked; native plugins require a restart after changes.
- Added CLI and Settings controls to check, install, update, or uninstall a user-installed app.
  App updates require an immutable GitHub release asset, a matching signed bundle, and a SHA-256
  digest. Existing installations are retained for recovery.

### Fixed

- Restored GitHub account sessions off the main UI thread so Keychain lookup cannot block launch.
- Moved plugin commands out of the Plugins navigation pane; they remain available through their
  registered command actions.

## 0.22.0

### Added

- Bundled the first-party C/C++ Support plugin with C/C++ syntax tokens, a Rust-owned clangd
  session, live inline diagnostics, Go to Definition, header/source switching, and explicit
  clang-format formatting when the tools are available.
- Expanded the public plugin ABI with syntax providers, active file/workspace paths, diagnostics,
  source navigation, and an optional unload callback. Existing ABI-1 plugin prefixes remain valid.
- Added an actual clangd integration test and plugin lexer/LSP protocol tests.
- Added a gated first-party release workflow for the C/C++ plugin and distinct required registry
  validation on every pull request.
- Published C/C++ Support 0.1.0 as a checksum-verified, immutable Official registry release.

### Fixed

- Re-sign the app bundle after a bundled plugin changes, even when the app executable is unchanged.
- Replace Cargo's absolute C/C++ plugin install name with a portable one, and strip build-only
  symbols from the release copy so hosted-runner paths cannot enter public binaries.

## 0.21.0

### Added

- Added a Rust-owned contribution registry with duplicate-ID and shortcut-chord checks.
- Added native plugin contributions for keyboard shortcuts, File menu actions, scrollable
  Plugins-panel views, bounded editor overlays, and extension-specific formatters.
- Kept per-plugin API contexts stable for late registration and refreshed live UI contributions.
- Added registry, host, and sample-plugin coverage for these extension points.

## 0.20.0

### Added

- Rust-owned document text, save state, and bounded undo/redo history behind an opaque C ABI.
  The C++ editor maintains a drawing mirror and applies UTF-16 edit ranges through Rust.
- Native plugin ABI functions for typed string properties, selection access, and range editing.
  Plugins can now change the editor canvas color and font, in addition to existing numeric
  typography and behavior properties.
- Rust and C++ boundary tests for Unicode edits, history, and dirty-state transitions.

### Changed

- Editor edits and save-state checks now consult the Rust document core rather than Objective-C++
  text/history storage.

## 0.19.1

### Fixed

- Redrew the Explorer's New File control as a compact folded-page icon with its plus inside the
  page and more space between the file and folder controls.
- Made the custom file dialog panel, file list, and selected-row fill opaque so Home content cannot
  bleed through the selection.
- Treat directory symlinks as folders in the Explorer and file browser, including Open Folder.

## 0.19.0

### Added

- Show hidden files and folders in the Explorer tree and Kinetic's Open, Save, and folder dialogs.
- Add a project New File control and dialog. Created files are opened immediately, revealed in the
  shared Explorer tree, and never overwrite an existing path.
- Add Kinetic-drawn context menus to tabs, Explorer rows and background, file-browser entries and
  filename field, Home recent projects, and the Search query.

### Changed

- Allow dot-prefixed names when creating project files and folders.

## 0.18.1

### Fixed

- Generated the OAuth badge with a navy canvas matching its GitHub background, removing the white
  corners around the Kinetic icon.

## 0.18.0

### Added

- Added GitHub sign-in through Kinetic's public OAuth app and GitHub's device authorization flow.
  The custom titlebar account panel shows the verification code, connection status, and sign-out.
- Added repository-scope authorization for future Git integration, Keychain-backed session storage,
  token refresh, and tests for device-code validation and requested scopes.
- Show the signed-in GitHub profile and avatar, and keep the File menu clear of the Home logo.

## 0.17.1

### Changed

- Expanded the public repository ignore rules for local configuration, editor state, generated
  output, diagnostics, and credential files. A local `.fiddleaudit` denylist stays untracked.

## 0.17.0

### Added

- Added a GitHub-backed plugin publication registry with immutable release entries, deterministic
  catalog generation, SHA-256 asset verification, publisher identity checks, and a project-owned
  Official policy.
- Added a plugin release drafting tool, registry regression tests, PR validation, and a GitHub
  Pages workflow for the public catalog.

## 0.16.1

### Fixed

- Moved native plugin configuration and loading to the portable `~/.kinetic/` dot-directory;
  Kinetic no longer reads the macOS Application Support location for plugins.

## 0.16.0

### Added

- Added live plugin-loading policy from the optional user `config.toml`: global enablement and an
  exact-filename disable list. Disabled libraries are skipped before native initialization.
- Added fail-closed validation for invalid plugin policy, a visible Plugins-panel error, defaults,
  schema, usage documentation, and regression tests.

## 0.15.0

### Added

- Added a versioned native C plugin ABI and loader for local Rust or C++ dynamic libraries.
- Added editor property access, command registration, document events, UTF-8 document snapshots,
  and selection replacement. Loaded plugin commands appear in the Plugins panel.
- Exposed letter spacing through the same property API used for editor font size, line height,
  indentation, syntax, gutter, and scrolling controls. Letter spacing affects text drawing and
  caret, selection, and scrolling measurements.
- Added a native sample plugin and host regression test.

## 0.14.0

### Changed

- Moved the editor Search icon from the tab strip to the custom titlebar. The Search dropdown now
  opens directly beneath it, while the icon remains hidden on Home and reflects open/hover state.

## 0.13.0

### Added

- Added automatic indentation on Return, including preservation of existing spaces or tabs,
  block indentation for braces and Python or shell control lines, and a blank indented line when
  splitting an empty bracket pair.
- Added configurable tab stops, Shift-Tab outdent, matching bracket and quote insertion, selection
  wrapping, closer skipping, paired Backspace, and closing-brace outdent.
- Added live Tab Width, Auto Indent, and Auto Pairs controls on the custom scrolling Settings page.

## 0.12.0

### Added

- Added built-in syntax highlighting for shell, Python, C/C++, Rust, Go, Java, JavaScript,
  TypeScript, Swift, Zig, C#, Kotlin, JSON/JSONC, TOML/YAML, HTML/XML, and CSS. Extensionless shell
  and Python scripts are recognized by shebang. Multiline comments and Python triple-quoted strings
  retain their color across lines.
- Added a live Syntax Highlighting switch to the custom Settings page and lexical regression tests.

## 0.11.0

### Added

- Added a compact top-right Search dropdown with in-file matching, result navigation, match-case
  toggle, and animated opening and closing. Command-F opens file search; Command-Shift-F switches to
  project search in the same control.
- Highlighted in-file matches in the editor and made result rows identify both line and column.

### Changed

- Moved project search out of the activity rail and into the top-right dropdown, preserving
  project-wide search and its shared state across document tabs.

## 0.10.0

### Added

- Added project-wide Search with Command-Shift-F, live filename and UTF-8 text matches, match-case
  control, clickable results that open at the matching line, and unsaved open-file text matches.
- Capped feature and patch version components at 99 with automatic rollover through `1.0.0`.
- Added an Explorer New Folder action and custom folder-creation dialog with nested destination
  browsing, name validation, duplicate protection, and immediate tree refresh.
- Retained multi-document tabs with independent text, selection, undo history, scrolling, file URL,
  save state, direct tab activation and closing, and previous/next tab shortcuts.
- Persisted recent workspace folders with custom Home rows that reopen the selected project.
- Custom translucent macOS window chrome, traffic controls, File menu, and branded Home screen.
- Custom editable text surface with tabs, dirty-state indication, line numbers, caret navigation,
  vertical and horizontal scrolling, and overflow indicators.
- Mouse caret placement, shift-click extension, drag selection, selection-aware editing, and an
  editor I-beam cursor.
- Kinetic-drawn editor context menu with live Undo, Redo, Cut, Copy, Paste, and Select All states.
- Standard editing shortcuts plus Command line/document navigation, Option word navigation and
  deletion, Shift selection extension, and bounded undo/redo history.
- Compact editor-only Kinetic activity rail with refined Explorer, Search, Source Control/GitHub,
  Plugins, and Settings icons, animated panels, and a working Explorer Open File action.
- Real Open Folder workflow with a sorted, expandable, scrollable Explorer file tree.
- Dedicated Settings page with live font size, line height, line-number, scroll-indicator, and
  natural-scrolling controls.
- Custom folder-and-file browser for opening and saving UTF-8 documents.
- Central keyboard shortcut routing for new, open, save, close, minimize, hide, quit, and fullscreen.
- Custom ease-out-cubic tween engine for Home, editor, and modal transitions.
- Embedded command-line client, application packaging, installation, icon generation, and release
  checksum automation.
- MacPorts release packaging with generated checksums, app-bundle installation, and an embedded CLI
  symlink.
- Version consistency and public-source audit scripts.

### Fixed

- Moved Explorer folder expansion, tree scrolling, and active-panel state to the window-level project
  session so document tabs never own or reset the workspace.
- Reflowed the editor viewport, gutter, caret, selections, scrolling, and mouse hit testing around
  the activity panel's live width instead of rendering document text underneath Explorer.
- Preserved the active Explorer or activity-panel section when opening, switching, or closing tabs.
- Enabled Open Folder in the custom File menu and renamed its close action from Close Window to
  Close Tab so the visible command matches its behavior.
- Kept activity-panel content visible during its closing animation and added compact section header
  strips and dividers for clearer hierarchy without heavy accordion styling.
- Clipped activity-panel text, aligned plugin content, added real panel buttons, and kept the arrow
  cursor over activity controls.
- Corrected natural scrolling direction in the file browser.
- Enabled ARC for the Objective-C++ interface to keep browser state alive safely.
- Made the square traffic control enter fullscreen while title-bar double-click maximizes.

## 0.1.0

- Established the Apache-2.0 project, Rust/C++ ABI, macOS application bundle, CLI, branding,
  documentation, CI, and packaging foundation.
