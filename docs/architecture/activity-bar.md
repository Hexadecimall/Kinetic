# Activity bar

The activity bar is a compact Kinetic-drawn rail shown only inside the editor. Its initial sections
are Explorer, Search, Source Control/GitHub, Plugins, and Settings. Selecting a section opens its
side panel; selecting it again collapses the panel. The rail stays close to the editor surface color
so it reads as navigation rather than a separate dark column. Opening and closing use the same
ease-out motion; panel content remains rendered through the closing tween instead of disappearing
before the panel reaches the rail.
The editor viewport, gutter, caret, selections, hit testing, and scroll bounds follow the panel's
live animated width, so expanded workspace UI never overlays or clips document text.

Explorer labels the current document as Open in Editor and provides distinct Open File and Open
Folder actions. Opening a folder builds a sorted, expandable, scrollable file tree; selecting a file
opens it in the editor. Compact low-contrast header strips and single-edge dividers group the open
document, workspace, search, repository, and installed-plugin sections without accordion styling or
non-functional disclosure affordances. Search, Source Control/GitHub, and Plugins remain honest integration
surfaces: they display current availability without pretending that workspace indexing, repository
discovery, account connections, or third-party plugin loading already exist.

Settings opens a dedicated editor page instead of a narrow side panel. The first live controls cover
font size, line height, line-number visibility, scroll-indicator visibility, and natural scrolling.

The rail, panel, icons, selection indicator, hover treatment, section headers, dimensions, opening
and closing animation durations, visibility, section order, and contributed sections belong to the
settings and plugin API contract.
The current preview records those defaults in `config/defaults/kinetic.toml` while runtime settings
loading is still being built.
