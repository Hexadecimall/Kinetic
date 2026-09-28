# Settings surface

The Settings activity and Command-Comma open a rounded, Kinetic-drawn overlay above the workspace.
Settings and Plugins preserve the underlying document tabs and Explorer. Both animate open and
closed; Escape, Command-W, the close button, or a backdrop click dismiss the panel.

Settings has searchable Appearance, Indentation, Completion, Navigation, Interface, and
Application categories. The 23 preference controls update open tabs immediately. Number controls
use a centered value between compact minus/plus buttons. Switch positions and colors tween from
their current state, including when toggled again mid-animation. Reduced Motion disables these
transitions. Success is silent; a failed preference write shows an error.

Supported controls:

- Font Size: 8 through 28 points.
- Font: system monospace, Menlo, Monaco, or Courier.
- Line Height: 14 through 40 points.
- Letter Spacing: -2 through 8 points, in quarter-point increments.
- Theme: Kinetic Dark, Midnight, or Graphite.
- Current Line: optional subtle highlight behind the caret's line.
- Diagnostics: show or hide diagnostic underlines and hover details without stopping clangd.
- Line Numbers: visible or hidden.
- Scroll Indicators: visible or hidden.
- Natural Scrolling: enabled or disabled.
- Syntax Highlighting: enabled or disabled for recognized source files.
- Tab Width: 1 through 16 columns per tab stop.
- Insert Tab Characters: choose literal tabs or spaces for new indentation.
- Indent Unit Navigation: move the caret across leading spaces one indentation level at a time.
- Indent Guides: show subtle indentation lines and leading-space/tab markers.
- Auto Indent: preserve the current line's indentation on Return and indent inside blocks.
- Auto Pairs: insert matching brackets and quotes, skip existing closing characters, and remove
  empty pairs with Backspace.
- Autocomplete: on/off, minimum prefix (1–8), and maximum results (1–32). New configurations
  default to one character and 12 results; C/C++ member access can trigger clangd immediately.
- Panel and switch animations: enable/disable, with duration from 80 to 400 milliseconds.
- Preferred Tab Width: 100 through 240 points; tabs still shrink to fit available space.

Backspace removes one indentation unit in leading whitespace. The settings list scrolls in
shorter windows. Indentation and autocomplete settings are read from and saved to
`~/.kinetic/config.toml`. Theme selection remains in `~/.kinetic/theme.toml`. Other numeric
preferences persist through the Rust backend in `~/.kinetic/editorSettings.json`, keyed by their
plugin property names. Writes preserve unrelated keys and refuse to replace malformed files.
Loaded values pass through the same range checks as plugin requests. Plugin property changes
remain session overrides unless changed through Settings.

The defaults and schema describe the settings contract; they are not a complete runtime TOML
loader. Layered workspace TOML, Lua loading, and plugin-contributed Settings controls remain
future work. Application update/install/uninstall actions remain in their own category and
retain confirmation for installation and removal.
