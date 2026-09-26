# Tabs and recent projects

Each open document owns a retained editor view. Text, selection, caret, undo and redo stacks,
scroll position, file URL, and dirty state remain intact when another tab becomes active. Opening a
file already present in the tab set activates the existing document instead of creating a duplicate.
The active activity-bar section and Explorer tree are window-level workspace state. Opening,
closing, or switching documents carries the project folder, expanded directories, tree scroll
position, and active panel forward instead of attaching them to the old tab. Closing the final
document retains that project state for the next document opened in the same window.

Tabs are drawn by Kinetic. Clicking a tab activates it, its close control removes that document, and
closing the active tab selects the nearest remaining document. Closing the final tab returns to
Home. Command-Shift-Left Bracket and Command-Shift-Right Bracket cycle through tabs with wrapping.

Opening a workspace folder moves it to the front of a bounded recent-project list stored in the
application defaults domain. Missing folders are filtered before display. Home draws the project
name and truncated parent path as custom rows; selecting one restores that workspace and opens an
editor when needed.

Tab widths, dirty markers, recent-list limits, path visibility, colors, shortcuts, and transition
timings are settings and plugin API contract points. The current implementation establishes their
behavior while the typed runtime settings registry is still being built.
