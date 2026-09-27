# Changelog

All notable Kinetic changes are recorded here. Versions use `main.feature.patch`.

## 0.18.0 - Unreleased

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
