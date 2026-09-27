# Architecture

Kinetic is a native editor with a custom GPU-rendered interface and a deliberately narrow boundary
between its C++ platform/rendering layer and Rust editor core.

## Ownership

### C++, Objective-C++, and Metal

- Application lifecycle and macOS integration
- Windows, displays, input methods, accessibility, menus, drag and drop
- GPU device management, compositing, text presentation, and UI primitives
- Frame scheduling, animation, hit testing, and native surface integration
- Custom window chrome, traffic controls, and in-window application menus
- Custom file browsing, document presentation, scrolling, and tween execution

### Rust

- Document text, edit application, dirty state, and bounded undo/redo history
- Plugin contribution metadata and collision rules for commands, shortcuts, menus, panels,
  overlays, and formatters
- Planned ownership of selections, workspace state, search, settings, and language tooling;
  these still have Objective-C++ implementations in the current preview
- Planned settings, TOML configuration, and Lua automation ownership
- Planned project discovery, tasks, language tooling, and LSP lifecycle ownership
- Long-term plugin capability policy

### ABI boundary

The internal boundary and native plugin surface use versioned C-compatible functions, opaque
handles, explicit ownership, and fixed-width types. Rust and C++ object layouts never cross the
boundary. Rust owns one document handle per editor tab. The C++ view retains a synchronized text
mirror for text layout and drawing; edit ranges use UTF-16 offsets at the boundary and Rust stores
UTF-8. Keystroke, text-layout, and per-glyph rendering hot paths stay within their owning side.
The current native plugin host lives in Objective-C++ because the first exposed properties control
the existing custom editor surface. It loads local dynamic libraries through the C ABI; native
plugins never receive view-object pointers.

## Current editor slice

The current macOS preview has a custom text surface, retained multi-document tabs with independent
editing state, dirty-state presentation, persisted recent projects, a custom folder/file browser,
UTF-8 open/save flow, mouse caret placement and drag selection, editing shortcuts, bounded undo/redo
history, basic syntax highlighting, indentation and delimiter assists, Kinetic-drawn context menus,
central shortcut router, and a
frame-driven cubic tween engine. AppKit supplies the window/event bridge, pasteboard access, and
compositor backdrop sampling; controls, browser rows, selection presentation, text presentation,
menus, and transitions are Kinetic-owned.

The editor activity rail and its Explorer, Source Control/GitHub, Plugins, and Settings sections are
also Kinetic-owned. File and project search share a top-right editor dropdown. Sections may be
hidden, reordered, replaced, or extended once the
settings and plugin registries are live; no section is a permanent hard-coded limit.

The titlebar account control is also Kinetic-drawn. GitHub authorization happens in the user's
browser through the public Kinetic OAuth app; Kinetic stores the resulting session in the macOS
Keychain and refreshes expiring tokens. See [`accounts.md`](accounts.md) for the current permissions
and sign-out behavior.

The dedicated Plugins page browses the public catalog and manages installed native plugins.
Commands are registered editor actions rather than Plugins-page rows. Contributed panel rows
remain supported by the plugin ABI, but no longer occupy the package browser. A plugin can set supported numeric and string properties, including letter
spacing, font, and editor canvas
color; subscribe to document events; edit an explicit UTF-16 range or selection; and register
shortcuts, File menu items, viewport overlays, extension-specific formatters, syntax providers,
diagnostics, and source navigation. Rust owns the
contribution registry; the Objective-C++ host retains callbacks and renders the custom UI in
process. The separately installable Rust C/C++ Support plugin runs clangd for live errors and Go
to Definition. Rust owns native document-word completion and the `[autocomplete]` dotfile
configuration; plugins can contribute completion items through the public C ABI. Settings
registration and arbitrary widget layouts are not yet exposed.

Opening a workspace folder populates an expandable file tree without using a native outline view.
The Explorer shows hidden entries and creates files and folders through Kinetic-drawn dialogs; the
custom Open and Save browsers show hidden entries too. Context menus serve tabs, project files,
browser rows and fields, recent projects, and search alongside the editor surface.
The dedicated Settings page exposes only controls already connected to editor behavior.

See [`tabs-and-recents.md`](tabs-and-recents.md) for document retention, tab switching, closing, and
recent-project persistence behavior.

Values embedded during this phase are defaults pending the settings registry. They must migrate to
typed settings without changing their established behavior. Plugins will reach supported behavior
through commands and settings rather than patching views directly.

## Language tooling

Kinetic discovers project-local tools, explicit configuration, standard toolchain locations, and
`PATH`. Opening a file without an available language server may trigger an installation offer that
names the package, publisher, and official status. No tool is downloaded silently.

Formatters and linters remain quiet until their capability is invoked. The core owns LSP process
lifecycle; installable language plugins provide tested defaults instead of core-only implementations.

## Platform direction

The initial target is Apple Silicon macOS 15 or newer using Metal. Platform and renderer interfaces
must keep future Intel macOS and Linux backends possible without reducing the quality of the first
platform.
