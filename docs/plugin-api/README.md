# Plugin API direction

Kinetic's plugin API will support native Rust and C++ plugins through a shared versioned C ABI.
Plugins may contribute commands, panels, language support, tasks, settings, themes, and custom UI.

Core editing and rendering paths are not implemented as plugins. Built-in language packs exercise
the same registries and data model where performance permits, while conformance plugins verify that
third-party capabilities remain complete.

Native plugins execute with the user's privileges. Installation must expose publisher provenance,
requested capabilities, and trust state. ABI version negotiation occurs before any plugin callback.

## Customization contract

Every user-facing Kinetic feature must expose a supported customization route. Typed settings cover
ordinary preferences and theme values; Lua may compose dynamic behavior; native Rust/C++ plugins
may register advanced commands, UI contributions, language tooling, and integrations. Defaults for
shortcuts, scrolling, animations, transparency, editor metrics, file-browser behavior, and custom
chrome are product defaults rather than fixed constraints.

Plugins interact through registries and stable handles. Direct access to Objective-C++ view objects
or Rust layouts is not part of the public API.
