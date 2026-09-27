# Settings surface

The Settings activity and Command-Comma open a dedicated Kinetic-drawn page. Its compact rows
animate in and out. Every visible control changes editor behavior across open tabs immediately:

- Font Size: 8 through 28 points.
- Line Height: 14 through 40 points.
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
- Autocomplete: on/off, minimum prefix (1–8), and maximum results (1–32).

Backspace removes one indentation unit in leading whitespace. The settings list scrolls in
shorter windows. Indentation and autocomplete settings are read from and saved to
`~/.kinetic/config.toml`. Other visible controls apply for the current session; a full typed
settings registry remains future work.

The values mirror the typed settings contract in `config/defaults/kinetic.toml` and
`config/schemas/settings.schema.json`. Layered workspace TOML and Lua loading remain future work.
