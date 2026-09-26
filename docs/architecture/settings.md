# Settings surface

The Settings activity opens a dedicated Kinetic-drawn page. It does not use AppKit controls. Every
visible control on the current page changes real editor behavior immediately:

- Font Size: 8 through 28 points.
- Line Height: 14 through 40 points.
- Line Numbers: visible or hidden.
- Scroll Indicators: visible or hidden.
- Natural Scrolling: enabled or disabled.
- Syntax Highlighting: enabled or disabled for recognized source files.
- Tab Width: 1 through 16 spaces per tab stop.
- Auto Indent: preserve existing spaces or tabs on Return and indent inside blocks.
- Auto Pairs: insert matching brackets and quotes, skip existing closing characters, and remove
  empty pairs with Backspace.

The settings list scrolls in shorter windows.

The page intentionally omits settings that are only planned. The values mirror the typed settings
contract in `config/defaults/kinetic.toml` and `config/schemas/settings.schema.json`. Persistence and
layered TOML/Lua loading remain part of the settings-registry milestone; this preview applies values
to the active editor immediately.
