# Activity bar

The activity bar is a compact Kinetic-drawn rail shown only inside the editor. Its initial sections
are Explorer, Source Control/GitHub, Plugins, and Settings. Selecting a section opens its
side panel; selecting it again collapses the panel. The rail stays close to the editor surface color
so it reads as navigation rather than a separate dark column. Opening and closing use the same
ease-out motion; panel content remains rendered through the closing tween instead of disappearing
before the panel reaches the rail.
The editor viewport, gutter, caret, selections, hit testing, and scroll bounds follow the panel's
live animated width, so expanded workspace UI never overlays or clips document text.

Explorer labels the current document as Open in Editor and provides distinct Open File and Open
Folder actions. Opening a folder builds a sorted, expandable, scrollable file tree; selecting a file
opens it in the editor. The project header's folder-plus control opens a Kinetic-drawn New Folder
dialog. It creates a folder at the project root or inside a browsed/selected subfolder, rejects
duplicate and invalid names, and reveals the result in the shared Explorer tree. Creation stays
inside the active window's project. Compact low-contrast header strips and single-edge dividers
group the open document, workspace, repository, and installed-plugin sections without accordion
styling or non-functional disclosure affordances. Source Control/GitHub and Plugins remain honest
integration surfaces: they do not pretend repository discovery, account connections, or third-party
plugin loading already exist.

Search lives in a Kinetic-drawn dropdown anchored to the top-right of the editor tab strip. The
button and Command-F open in-file search; Command-Shift-F opens project search. Both scopes show
live result rows and support match case, keyboard selection, and opening the selected match. In-file
search finds each occurrence, including multiple on one line, and highlights visible matches in the
editor. Project search scans filenames and UTF-8 lines off the UI thread, including unsaved text in
open files. Its query and results follow the window's project across tabs. Hidden files, package
contents, common generated folders, files over 1 MiB, and binary files are skipped; results stop at
300 matches or 10,000 scanned files.

Settings opens a dedicated editor page instead of a narrow side panel. The first live controls cover
font size, line height, line-number visibility, scroll-indicator visibility, and natural scrolling.

The rail, panel, icons, selection indicator, hover treatment, section headers, dimensions, opening
and closing animation durations, visibility, section order, and contributed sections belong to the
settings and plugin API contract.
The current preview records those defaults in `config/defaults/kinetic.toml` while runtime settings
loading is still being built.
