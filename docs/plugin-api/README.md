# Native plugin API (preview)

Kinetic 0.15.0 and later load local Apple Silicon `.dylib` plugins from
`~/.kinetic/plugins/` when the first editor tab opens. It does not
download, publish, update, or verify plugins. Only install code whose author is trusted: a native
plugin runs in Kinetic's process with the user's privileges and can crash the app.
Plugin loading can be disabled globally or per `.dylib` filename through the optional
`[plugins]` table in `~/.kinetic/config.toml`; see
[`config/README.md`](../../config/README.md). Configuration is checked before `dlopen`.

The public ABI is [`include/kinetic/pluginApi.h`](../../include/kinetic/pluginApi.h). A Rust or C++
plugin exports `kineticPluginEntry`, returning a static `KineticPluginDescriptor` with ABI version,
structure size, metadata, and a `start` callback. The host calls `start` on the main thread after
version validation. The `KineticPluginApi` pointer stays valid for the lifetime of the host. Its
`context` must be passed back to each API function; plugins must not inspect or free it. All calls
and callbacks currently run on the main thread. Return value `0` means success; `-1` means the
requested operation is unavailable or invalid. UTF-8 text must be valid. ABI structures may grow
by appending fields; callers check `abiVersion` and `structSize` before using fields.

The current host supports:

| Function | Effect |
| --- | --- |
| `setNumber`, `getNumber` | Read or change a supported numeric editor property. Changes apply to all tabs and future tabs in this window. |
| `registerCommand` | Add an ID, visible title, and callback to the Plugins panel. IDs must be unique. |
| `subscribeEvent` | Listen for `document.activated` or `document.changed`. |
| `copyDocumentUtf8` | Return the active document's byte length. Pass a buffer larger than the returned length to receive NUL-terminated UTF-8. |
| `replaceSelectionUtf8` | Replace the active selection using normal editor edit/dirty-state handling. |
| `setString`, `copyString` | Change or read a supported UTF-8 string property. `copyString` returns `UINT64_MAX` for an unknown property. |
| `getSelection`, `setSelection` | Read or set the active selection as a UTF-16 range. |
| `replaceRangeUtf8` | Replace an explicit UTF-16 document range through the Rust document core and normal undo/dirty handling. |
| `registerShortcut` | Bind a registered command to a single alphanumeric key and modifier mask. Duplicate plugin chords are rejected. |
| `registerFileMenuItem` | Add a registered command to Kinetic's custom File menu. |
| `registerPanel` | Add a titled Plugins-panel view with callback-supplied label and command-button rows. |
| `registerOverlay` | Draw bounded rectangle/text commands over the active editor viewport. |
| `registerFormatter` | Register a lowercase file extension and UTF-8 document formatter. Format Document appears in the File menu for matching files. |

These five functions are appended to ABI version 1. Older plugins can keep using the original
structure prefix; new plugins must check `structSize` before reading the appended pointers. A
plugin retains its own API pointer and context for its lifetime, including registrations made
after `start` returns. Contributions belong to that plugin and are removed if `start` fails.
Callbacks and registrations run on the main thread. Shortcut modifiers use the
`kineticPluginModifier*` constants; a plugin shortcut may supersede a built-in shortcut.
Panel callbacks can return up to 32 rows per panel. Overlay callbacks can return up to 128 draw
commands per overlay and are clipped to the editor viewport. Coordinates and sizes are in points,
relative to the viewport; colors are `0xRRGGBBAA`. Formatter output is limited to 16 MiB,
must be valid UTF-8, and is applied as one undoable edit. Formatters run only on explicit
Format Document invocation, not on save.

Supported numeric property keys and ranges:

| Key | Accepted value |
| --- | --- |
| `editor.text.letterSpacing` | -2 to 8 points; changes glyph spacing and text measurements |
| `editor.text.fontSize` | 8 to 28 points |
| `editor.text.lineHeight` | 14 to 40 points |
| `editor.indentation.tabWidth` | Integer 1 to 16 |
| `editor.syntax.enabled` | 0 or 1 |
| `editor.gutter.lineNumbers` | 0 or 1 |
| `editor.scroll.indicators` | 0 or 1 |
| `editor.scroll.natural` | 0 or 1 |
| `editor.indentation.autoIndent` | 0 or 1 |
| `editor.delimiters.autoPairs` | 0 or 1 |

Supported string properties:

| Key | Accepted value |
| --- | --- |
| `editor.text.fontFamily` | Empty for the system monospace font, or an installed font's PostScript name (maximum 128 characters) |
| `editor.canvas.background` | `#RRGGBB` color; the editor's existing backdrop alpha is retained |

`tests/samplePlugin.cpp` is a compilable example; `kineticPluginHostTests` loads it and checks
property changes, command execution, event delivery, document editing, shortcuts, menus, panels,
formatting, and late registration. A third-party C++ plugin can be built with
`clang++ -std=c++20 -dynamiclib -I include myPlugin.cpp -o myPlugin.dylib`
from the repository root. Rust plugins can use `extern "C"` with matching `#[repr(C)]` structures;
no Rust or C++ internal object layout is exposed through the boundary.

## Customization contract

Every user-facing feature must eventually have a supported customization route. The property-key
ABI is an extensible entry point rather than a frozen list of ten preferences. Text layout remains
inside Kinetic's renderer: plugins change a property, not per-glyph callbacks. This keeps letter
spacing customizable without placing plugin dispatch in the drawing hot path.

The GitHub-backed publication flow and Official policy are documented in
[`registry/README.md`](../../registry/README.md). The current editor does not yet browse or install
from that catalog.

The current ABI does **not** yet expose every editor control. The Rust contribution registry now
owns metadata and collision rules for commands, shortcuts, menus, panels, overlays, and formatters;
the C++ host still owns native callbacks and rendering. Settings registration, arbitrary widget
layout, language tools, diagnostics, and file-system providers remain future work. Changing one
exposed property or registering an overlay does not imply arbitrary view control. The next backend
boundary work is moving selection, workspace search, and settings to Rust. API growth must preserve
old structure prefixes, check `structSize`, and avoid exposing Objective-C++ view pointers or unstable Rust
internals. Marketplace trust and official-publisher verification are separate future work, not
implied by a local plugin's metadata.
