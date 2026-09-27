# Built-in plugins

Built-in language packs and optional integrations live here. Performance-sensitive editor,
rendering, and language-tooling infrastructure remains in the core; built-ins provide configuration
and integration rather than duplicating those systems.

Built-ins use the same documented settings, command, theme, and capability registries available to
third-party plugins. Shipping a built-in-only customization hook is not acceptable.

[`cppSupport/`](cppSupport/) is the bundled C/C++ Support plugin. Its syntax, diagnostics,
navigation, and formatting use the public native plugin ABI.
