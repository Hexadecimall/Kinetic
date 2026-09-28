# Configuration sources

Kinetic configuration is layered from built-in defaults, user TOML, workspace TOML, Lua
automation, and plugin-provided settings. Later layers may override earlier layers only through a
registered typed setting.

- `defaults/kinetic.toml` records the product defaults currently represented by the interface.
- `schemas/settings.schema.json` describes the public settings shape.

The current preview loads `[plugins]`, `[autocomplete]`, and indentation fields under `[editor]`
at runtime; other sections remain a
migration contract for replacing temporary in-code defaults with the Rust settings registry. A
setting becomes supported only when its runtime wiring, validation, documentation, and plugin API
exposure land together.

Native plugin policy lives at `~/.kinetic/config.toml`. The supported
subset is a `[plugins]` table with `enabled = true` or `false` and a one-line `disabledFiles` array
of exact `.dylib` filenames. For example:

```toml
[plugins]
enabled = true
disabledFiles = ["example.dylib"]
```

The file is optional. If it is absent, installed local plugins load by default. C/C++ Support
is an installable Official plugin, not part of Kinetic.app. Add its installed `.dylib` filename to
`disabledFiles` to skip loading it without uninstalling it.
If the plugin
table is invalid or unreadable, no native plugin loads and the Plugins panel displays the error.
Disabled filenames are checked before opening libraries in `~/.kinetic/plugins/`. Changes take
effect on the next launch;
loaded native plugins cannot be safely unloaded in place.

The native autocomplete engine reads these user settings at editor startup:

```toml
[autocomplete]
enabled = true
minPrefix = 1
maxResults = 12
```

`minPrefix` accepts 1–8 characters and `maxResults` accepts 1–32 suggestions. C/C++ Support
uses clangd completion when installed; otherwise native document-word completion remains available.
Control-Space requests suggestions after one
character; C/C++ member access also triggers clangd without a prefix. Arrow keys select, Return or
Tab inserts, and Escape dismisses. Invalid autocomplete
values fall back to defaults.

The editor also reads and saves indentation preferences:

```toml
[editor]
tabWidth = 4
insertTabs = false
autoIndent = true
indentUnitNavigation = true
showIndentGuides = true
```

`insertTabs = false` inserts spaces to the next tab stop; `true` inserts a literal tab. Backspace
removes one indentation unit while the caret is in leading whitespace. Other editor configuration
keys remain part of the future settings registry.
`indentUnitNavigation` moves the caret by tab stops inside leading whitespace, including
space-based indentation, and snaps mouse placement to the nearest stop. `showIndentGuides` draws
subtle indentation guides and marks leading spaces and literal tabs.

Tab sizing and recent-project presentation are recorded in the same contract; recent paths are
runtime user data stored by the application and never written into the repository.
