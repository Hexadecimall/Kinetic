# Planned workflows

## Workspace multitasking

Add horizontal and vertical editor splits with independent tab groups, draggable dividers,
keyboard navigation between panes, and tab movement between groups. Multiple views of the same
document must share one Rust-owned buffer and undo history while retaining independent selection
and scroll positions. Persist pane layouts and restore sessions without losing unsaved work.

## AI panel

Add a configurable panel with separate conversation tabs, selectable providers and models,
response-length controls, editable prompts, explicit context selection, and per-tool permissions.
Keep presentation in C++ and conversation, provider, and tool state in Rust. Expose configuration
and plugin API hooks for commands, shortcuts, layout, and context providers. Proposed edits need
reviewable diffs; network requests and tool execution must respect configured permissions.

## Daily editing

Complete integrated terminal sessions, Git status/diff/stage/commit/push workflows, multi-cursor
editing, language-server rename and references, debugger integration, and broader language support.
These are roadmap items, not claims of implemented functionality.

## Settings migration

Once Kinetic is ready for daily editing, add settings migration from VS Code, Cursor, Zed, and
JetBrains IDEs. Import supported themes, keybindings, editor preferences, and workspace settings
with a preview, clear unsupported-setting reporting, and a backup of existing Kinetic settings.
Migration is deferred until the corresponding Kinetic settings are implemented and stable.
