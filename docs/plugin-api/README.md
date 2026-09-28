# Native plugin API (preview)

Kinetic 0.15.0 and later load local Apple Silicon `.dylib` plugins from
`~/.kinetic/plugins/` when the first editor tab opens. Official C/C++ Support is bundled with
Kinetic.app and loaded through the same public ABI before user plugins. The package manager
installs, updates, and verifies other catalog assets; the plugin host loads installed libraries.
Only install code whose author is trusted: a native
plugin runs in Kinetic's process with the user's privileges and can crash the app.
Plugin loading can be disabled globally or per `.dylib` filename through the optional
`[plugins]` table in `~/.kinetic/config.toml`; see
[`config/README.md`](../../config/README.md). Configuration is checked before `dlopen`.

The public ABI is [`include/kinetic/pluginApi.h`](../../include/kinetic/pluginApi.h). A Rust or C++
plugin exports `kineticPluginEntry`, returning a static `KineticPluginDescriptor` with ABI version,
structure size, metadata, and a `start` callback. The host calls `start` on the main thread after
version validation. The `KineticPluginApi` pointer stays valid for the lifetime of the host. Its
`context` must be passed back to each API function; plugins must not inspect or free it. Calls
are main-thread-only unless a function explicitly states otherwise. Return value `0` means success; `-1` means the
requested operation is unavailable or invalid. UTF-8 text must be valid. ABI structures may grow
by appending fields; callers check `abiVersion` and `structSize` before using fields.

The current host supports:

| Function | Effect |
| --- | --- |
| `setNumber`, `getNumber` | Read or change a supported numeric editor property. Changes apply to all tabs and future tabs in this window. |
| `registerCommand` | Add an ID, visible title, and callback that shortcuts, menu items, and plugin controls can invoke. IDs must be unique. |
| `subscribeEvent` | Listen for `document.activated` or `document.changed`. |
| `copyDocumentUtf8` | Return the active document's byte length. Pass a buffer larger than the returned length to receive NUL-terminated UTF-8. |
| `replaceSelectionUtf8` | Replace the active selection using normal editor edit/dirty-state handling. |
| `setString`, `copyString` | Change or read a supported UTF-8 string property. `copyString` returns `UINT64_MAX` for an unknown property. |
| `getSelection`, `setSelection` | Read or set the active selection as a UTF-16 range. |
| `replaceRangeUtf8` | Replace an explicit UTF-16 document range through the Rust document core and normal undo/dirty handling. |
| `registerShortcut` | Bind a registered command to a single alphanumeric key and modifier mask. Duplicate plugin chords are rejected. |
| `registerFileMenuItem` | Add a registered command to Kinetic's custom File menu. |
| `registerPanel` | Register a titled callback-supplied panel model. The package browser does not display contributed panels; a dedicated host surface is still pending. |
| `registerOverlay` | Draw bounded rectangle/text commands over the active editor viewport. |
| `registerFormatter` | Register a lowercase file extension and UTF-8 document formatter. Format Document appears in the File menu for matching files. |
| `registerSyntaxProvider` | Supply line-local UTF-16 syntax tokens for a file extension. State carries multiline lexer context between lines. |
| `copyActiveFilePath`, `copyWorkspacePath` | Copy the active absolute file path or window workspace path as UTF-8; `UINT64_MAX` means unavailable. |
| `publishDiagnostics` | Publish up to 2,048 line/column diagnostics for an absolute file path. Safe to call from a worker thread; the host updates the UI on the main thread. |
| `openLocation` | Open an absolute file path and reveal a 1-based line and 0-based UTF-16 column. Safe to call from a worker thread. |
| `registerCompletionProvider` | Contribute up to 32 labeled completion items for a file extension and prefix to Kinetic's native autocomplete popup. |
| `publishDiagnosticsV2` | Publish diagnostics with an explicit `kineticPluginDiagnosticFixAvailable` flag without changing the layout of older diagnostics. |
| `registerDiagnosticFixProvider` | Register a quick-fix callback for an extension; the editor calls it when a user clicks Fix on a flagged diagnostic. |

These functions are appended to ABI version 1. Older plugins can keep using the original
structure prefix; new plugins must check `structSize` before reading the appended pointers. A
plugin retains its own API pointer and context for its lifetime, including registrations made
after `start` returns. Contributions belong to that plugin and are removed if `start` fails.
An optional trailing `stop` callback in `KineticPluginDescriptor` is invoked before the host
unloads the library; older descriptors without it remain valid. Registration and editor-event
callbacks run on the main thread. Syntax callbacks run during rendering on the main thread;
only `publishDiagnostics`, `publishDiagnosticsV2`, and `openLocation` explicitly support worker-thread calls. Completion
callbacks run synchronously on the main thread while suggestions refresh and must return quickly;
each label, insertion, and detail is limited to 95 UTF-8 bytes. No plugin draws the popup.
Shortcut modifiers use the
`kineticPluginModifier*` constants; a plugin shortcut may supersede a built-in shortcut.
Panel callbacks can return up to 32 rows per panel. Overlay callbacks can return up to 128 draw
commands per overlay and are clipped to the editor viewport. Coordinates and sizes are in points,
relative to the viewport; colors are `0xRRGGBBAA`. Formatter output is limited to 16 MiB,
must be valid UTF-8, and is applied as one undoable edit. Formatters run only on explicit
Format Document invocation, not on save.
Syntax token kinds use the `kineticPluginSyntax*` constants and per-line UTF-16 offsets.
Diagnostics use 1-based lines, 0-based UTF-16 columns, and severity constants in the header.
Fix callbacks run on the main thread, receive the selected diagnostic range, and return zero only
after applying a verified action. A provider should reject stale or cross-file edits. Hosts built
before these optional trailing ABI fields remain compatible with older plugins.
The bounded callbacks do not receive Objective-C++ view pointers.

Supported numeric property keys and ranges:

| Key | Accepted value |
| --- | --- |
| `editor.text.letterSpacing` | -2 to 8 points; changes glyph spacing and text measurements |
| `editor.text.fontSize` | 8 to 28 points |
| `editor.text.lineHeight` | 14 to 40 points |
| `editor.text.fontPreset` | Integer 0 to 3: system monospace, Menlo, Monaco, Courier |
| `editor.currentLine.enabled` | 0 or 1 for the caret-line background |
| `editor.diagnostics.enabled` | 0 or 1 for diagnostic presentation; language servers stay active |
| `editor.tabs.preferredWidth` | 100 to 240 points |
| `interface.theme` | Integer 0 to 2: Kinetic Dark, Midnight, Graphite; persists via the theme store |
| `interface.motion.enabled` | 0 or 1 for Settings/Plugins panels and Settings switches |
| `interface.motion.duration` | 80 to 400 milliseconds; system Reduced Motion takes precedence |
| `editor.indentation.tabWidth` | Integer 1 to 16 |
| `editor.indentation.insertTabs` | 0 for spaces, 1 for literal tab characters |
| `editor.indentation.unitNavigation` | 0 for character navigation, 1 for indentation units |
| `editor.indentation.guides` | 0 or 1 for indentation guides and markers |
| `editor.syntax.enabled` | 0 or 1 |
| `editor.gutter.lineNumbers` | 0 or 1 |
| `editor.scroll.indicators` | 0 or 1 |
| `editor.scroll.natural` | 0 or 1 |
| `editor.indentation.autoIndent` | 0 or 1 |
| `editor.delimiters.autoPairs` | 0 or 1 |
| `editor.autocomplete.enabled` | 0 or 1 |
| `editor.autocomplete.minPrefix` | Integer 1 to 8 |
| `editor.autocomplete.maxResults` | Integer 1 to 32 |

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

The property-key ABI exposes the settings listed above. Text layout stays in Kinetic's renderer;
property updates do not add per-glyph plugin callbacks.

The GitHub-backed publication flow and Official policy are documented in
[`registry/README.md`](../../registry/README.md). The Plugins page browses and installs from that catalog.

[`C/C++ Support`](../../plugins/official/cppSupport/README.md) is a first-party example of the
language hooks. It ships in the app bundle; separately published versions are available through
the Official catalog.

The current ABI does **not** yet expose every editor control. The Rust contribution registry now
owns metadata and collision rules for commands, shortcuts, menus, panels, overlays, and formatters;
the C++ host still owns native callbacks and rendering. Syntax providers, diagnostics, and
location navigation and completion are now public hooks. Settings registration, arbitrary widget
layout, additional language-tool methods, and file-system providers are not exposed. Selection and
workspace search remain in Objective-C++; numeric preference persistence is in Rust. API changes must preserve
old structure prefixes, check `structSize`, and avoid exposing Objective-C++ view pointers or unstable Rust
internals. Official status comes from the registry's publisher policy, not local plugin metadata.
