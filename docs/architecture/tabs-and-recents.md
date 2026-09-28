# Tabs and recent projects

Each open document owns a retained editor view. Text, selection, caret, undo and redo stacks,
scroll position, file URL, and dirty state remain intact when another tab becomes active. Opening a
file already present in the tab set activates the existing document instead of creating a duplicate.
The active activity-bar section and Explorer tree are window-level workspace state. Opening,
closing, or switching documents carries the project folder, expanded directories, tree scroll
position, and active panel forward instead of attaching them to the old tab. Closing the final
document retains that project state for the next document opened in the same window.

Tabs are drawn by Kinetic. Clicking a tab activates it, its close control removes that document,
and right-clicking it offers a custom Close Tab menu. Closing the active tab selects the nearest
remaining document; closing the final tab returns to Home when no project is open. An open project
instead retains an empty workspace, not a new Untitled document. Opening a folder or recent project
also uses that empty workspace until an actual file is opened. Command-Shift-Left Bracket and
Command-Shift-Right Bracket cycle through tabs with wrapping. Recent-project rows have custom
Open Project and Copy Path menus.

The tab strip collapses when no document tabs are visible. The activity rail and Explorer then
start directly beneath the titlebar; opening a document restores the strip. Settings and Plugins
are rounded overlays, not document tabs, and do not reserve tab-strip space.

Opening a workspace folder moves it to the front of a bounded recent-project list stored in the
application defaults domain. Missing folders are filtered before display. Home draws the project
name and truncated parent path as custom rows; selecting one restores that workspace without
creating an Untitled file.

Settings exposes preferred tab width. Other customization limits are documented in
[`settings.md`](settings.md) and the [plugin API](../plugin-api/README.md).
