# Third-party source

All third-party source dependencies are stored as pinned snapshots beneath this directory.

Each dependency must include:

- Its upstream license
- Its upstream project URL
- The exact release version or commit
- A reproducible update procedure
- Any local patches as separate, reviewable patch files

Builds must not download executable code or unpinned source. Adding or updating a dependency also
requires updating the repository's third-party notices.

Dependency updates follow Kinetic's `main.feature.patch` rules and require a changelog entry when
they affect behavior, compatibility, packaging, licensing, or public APIs.
