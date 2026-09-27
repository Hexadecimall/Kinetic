# Official plugins

Official language packs and optional integrations live here as separately published plugins.
Performance-sensitive editor and rendering infrastructure remains in the core. This directory
contains source, not libraries bundled into Kinetic.app.

Official plugins use the same documented settings, command, theme, and capability registries
available to third-party plugins. Shipping an Official-only customization hook is not acceptable.

[`cppSupport/`](cppSupport/) is the separately installable C/C++ Support plugin. Its syntax,
diagnostics, navigation, and formatting use the public native plugin ABI.
