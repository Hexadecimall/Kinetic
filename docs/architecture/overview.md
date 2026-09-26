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

- Text buffers, selections, edits, history, and workspace state
- Commands, settings, TOML configuration, and Lua automation
- Project discovery, tasks, language tooling, and LSP lifecycle
- Plugin discovery, capability policy, and stable API implementation

### ABI boundary

The internal boundary and native plugin surface use versioned C-compatible functions, opaque
handles, explicit ownership, and fixed-width types. Rust and C++ object layouts never cross the
boundary. Keystroke, text-layout, and per-glyph rendering hot paths stay within their owning side.

## Current editor slice

The current macOS preview has a custom text surface, retained multi-document tabs with independent
editing state, dirty-state presentation, persisted recent projects, a custom folder/file browser,
UTF-8 open/save flow, mouse caret placement and drag selection, editing shortcuts, bounded undo/redo
history, a custom editor context menu, central shortcut router, and a frame-driven cubic tween
engine. AppKit supplies the window/event bridge, pasteboard access, and
compositor backdrop sampling; controls, browser rows, selection presentation, text presentation,
menus, and transitions are Kinetic-owned.

The editor activity rail and its Explorer, Search, Source Control/GitHub, Plugins, and Settings
panels are also Kinetic-owned. Sections may be hidden, reordered, replaced, or extended once the
settings and plugin registries are live; no section is a permanent hard-coded limit.

Opening a workspace folder populates an expandable file tree without using a native outline view.
The Explorer creates folders through a Kinetic-drawn dialog and refreshes the window's project tree.
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
lifecycle; built-in language packs provide tested defaults instead of separate implementations.

## Platform direction

The initial target is Apple Silicon macOS 15 or newer using Metal. Platform and renderer interfaces
must keep future Intel macOS and Linux backends possible without reducing the quality of the first
platform.
