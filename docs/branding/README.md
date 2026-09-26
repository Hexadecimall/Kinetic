# Kinetic brand

Kinetic's identity pairs structural electric blue with forward orange motion. The revised mark is
a clean geometric K with a blue stem and upper arm and an orange lower arm. It must remain recognizable at application-icon,
favicon, and toolbar sizes.

## Core palette

| Token | Value | Use |
| --- | --- | --- |
| Electric blue | `#4D8DFF` | Structure, focus, primary action |
| Kinetic orange | `#FF7A3D` | Motion, execution, active energy |
| Deep slate | `#2F3947` | Primary translucent dark surface |
| Raised surface | `#35404F` | Panels and elevated regions |
| Primary text | `#ECF3FF` | High-emphasis foreground |

The brand palette is not a permanent UI constraint. Themes may replace every semantic color,
metric, icon, font, effect, and animation exposed by the theme schema.

The Home screen must render the bundled application icon rather than recreating the mark in code.
This keeps the Dock, packaged application, documentation, and in-product identity synchronized.

Kinetic replaces the stock macOS traffic lights with compact geometric close, minimize, and zoom
controls. Only menus backed by current functionality appear beside them; the foundation exposes
`File` alone. Control colors, dimensions, menu spacing, and hover treatments are theme tokens.

## Assets

- `kinetic-mark.svg` is the primary transparent mark.
- `kinetic-app-icon.svg` is the source artwork for platform icons.
- `kinetic-lockup-dark.svg` is the dark-background horizontal lockup.
- `kinetic-mark-monochrome.svg` is for single-color contexts.

Keep clear space around the mark equal to at least one quarter of its width. Do not stretch,
rotate, outline, recolor individual blades, or place it on a low-contrast background.
