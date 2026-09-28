# Activity bar

The activity bar is a compact Kinetic-drawn rail shown only inside the editor. Its initial sections
are Explorer, Source Control/GitHub, Plugins, and Settings. Explorer and Source Control open a
side panel; Plugins and Settings open rounded overlays without changing the active side panel. The rail stays close to the editor surface color
so it reads as navigation rather than a separate dark column. Opening and closing use the same
ease-out motion; panel content remains rendered through the closing tween instead of disappearing
before the panel reaches the rail.
The editor viewport, gutter, caret, selections, hit testing, and scroll bounds follow the panel's
live animated width, so expanded workspace UI never overlays or clips document text.

Explorer labels the current document as Open in Editor and provides distinct Open File and Open
Folder actions. Opening a folder builds a sorted, expandable, scrollable file tree, including
dotfiles and hidden folders; selecting a file opens it in the editor. The project header has
New File and New Folder controls. Their Kinetic-drawn dialogs create inside the current project,
including a selected subfolder, reject duplicates, and reveal the result in the shared tree. A new
file opens in its own tab. Dot-prefixed names are valid. The same hidden entries appear in custom
Open and Save browsers. Explorer searches nested filenames in the current project, and custom
Open File/Open Folder browsers filter the current folder by name. Kinetic-drawn context menus provide file/folder creation and path copying
from the Explorer, and opening or path copying from file-browser rows. Directory symlinks are
navigable folders in both surfaces. The dialog panel, list, and selection fill are opaque, keeping
Home content from showing through a selected row. Compact low-contrast header
strips and single-edge dividers
group the open document, workspace, repository, and installed-plugin sections without accordion
styling or non-functional disclosure affordances. Source Control/GitHub remains an integration
placeholder. The Plugins page browses the public catalog, searches plugins and publishers, and
separates Discover from Installed. It shows description, publisher, Official status, version,
unrated state, and install/update/remove actions with a dedicated confirmation panel. Official
C/C++ Support is marked Included and cannot be removed from the app. Plugin commands remain
registered editor actions, not navigation items.
GitHub account connection lives in the titlebar.

Search lives in a Kinetic-drawn dropdown anchored beneath the Search icon at the right edge of the
custom titlebar. The icon appears only while an editor is open; it no longer occupies the tab strip.
The button and Command-F open in-file search; Command-Shift-F opens project search. Both scopes show
live result rows and support match case, keyboard selection, and opening the selected match. In-file
search finds each occurrence, including multiple on one line, and highlights visible matches in the
editor. Project search scans filenames and UTF-8 lines off the UI thread, including unsaved text in
open files. Its query and results follow the window's project across tabs. Hidden files, package
contents, common generated folders, files over 1 MiB, and binary files are skipped; results stop at
300 matches or 10,000 scanned files.

Settings opens a searchable, categorized overlay with animated switches and compact steppers.
Live controls cover editor type, scrolling, syntax highlighting, indentation, delimiter pairing,
autocomplete, themes, diagnostics, tab sizing, and panel motion. Application package
controls check for updates and manage a user-scoped installation with explicit confirmation.

The Explorer panel's right edge can be dragged to resize it; its width persists in
`~/.kinetic/layout.toml`. The Command Palette offers Kinetic Dark, Midnight, and Graphite themes,
persisted in `~/.kinetic/theme.toml`. Panel rearrangement is not implemented yet.

The rail, panel, icons, selection indicator, hover treatment, section headers, dimensions, opening
and closing animation durations, visibility, section order, and contributed sections belong to the
settings and plugin API contract.
The current preview records those defaults in `config/defaults/kinetic.toml` while runtime settings
loading is still being built.
