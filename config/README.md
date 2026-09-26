# Configuration sources

Kinetic configuration is layered from built-in defaults, user TOML, workspace TOML, Lua
automation, and plugin-provided settings. Later layers may override earlier layers only through a
registered typed setting.

- `defaults/kinetic.toml` records the product defaults currently represented by the interface.
- `schemas/settings.schema.json` describes the public settings shape.

The current preview does not load these files at runtime yet. They are the migration contract for
replacing temporary in-code defaults with the Rust settings registry. A setting becomes supported
only when its runtime wiring, validation, documentation, and plugin API exposure land together.
Tab sizing and recent-project presentation are recorded in the same contract; recent paths are
runtime user data stored by the application and never written into the repository.
