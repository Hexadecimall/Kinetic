# Configuration sources

Kinetic configuration is layered from built-in defaults, user TOML, workspace TOML, Lua
automation, and plugin-provided settings. Later layers may override earlier layers only through a
registered typed setting.

- `defaults/kinetic.toml` records the product defaults currently represented by the interface.
- `schemas/settings.schema.json` describes the public settings shape.

The current preview loads `[plugins]` and `[autocomplete]` user settings at runtime; other sections remain a
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
minPrefix = 2
maxResults = 8
```

`minPrefix` accepts 1–8 characters and `maxResults` accepts 1–32 suggestions. These settings
control document-word and plugin suggestions. Control-Space requests suggestions after one
character; arrow keys select, Return or Tab inserts, and Escape dismisses. Invalid autocomplete
values fall back to defaults. Other configuration sections in this file are currently ignored.

Tab sizing and recent-project presentation are recorded in the same contract; recent paths are
runtime user data stored by the application and never written into the repository.
