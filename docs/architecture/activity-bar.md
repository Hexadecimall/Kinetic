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
Folder actions. Opening a folder builds a sorted, expandable, scrollable file tree, including
dotfiles and hidden folders; selecting a file opens it in the editor. The project header has
New File and New Folder controls. Their Kinetic-drawn dialogs create inside the current project,
including a selected subfolder, reject duplicates, and reveal the result in the shared tree. A new
file opens in its own tab. Dot-prefixed names are valid. The same hidden entries appear in custom
Open and Save browsers. Kinetic-drawn context menus provide file/folder creation and path copying
from the Explorer, and opening or path copying from file-browser rows. Directory symlinks are
navigable folders in both surfaces. The dialog panel, list, and selection fill are opaque, keeping
Home content from showing through a selected row. Compact low-contrast header
strips and single-edge dividers
group the open document, workspace, repository, and installed-plugin sections without accordion
styling or non-functional disclosure affordances. Source Control/GitHub remains an integration
placeholder. Plugins lists locally loaded native libraries, registered commands, and scrollable
plugin-provided label/button views. Publishing and online installation are not implemented;
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

Settings opens a dedicated editor page instead of a narrow side panel. Live controls cover editor
type, scrolling, syntax highlighting, indentation, and delimiter pairing.

The rail, panel, icons, selection indicator, hover treatment, section headers, dimensions, opening
and closing animation durations, visibility, section order, and contributed sections belong to the
settings and plugin API contract.
The current preview records those defaults in `config/defaults/kinetic.toml` while runtime settings
loading is still being built.
