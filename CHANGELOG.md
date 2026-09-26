# Changelog

All notable Kinetic changes are recorded here. Versions use `main.feature.patch`.

## 0.12.0 - Unreleased

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
