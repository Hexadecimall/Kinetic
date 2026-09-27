# Vendored Cargo dependencies

These exact source snapshots support the separately installable Rust C/C++ Support plugin. Cargo resolves them
through `.cargo/config.toml`; normal builds do not fetch source. Each crate retains its upstream
license file(s) and Cargo checksum manifest. No local patches are applied.

| Crate | Version | License | Upstream |
| --- | --- | --- | --- |
| itoa | 1.0.18 | MIT OR Apache-2.0 | https://github.com/dtolnay/itoa |
| memchr | 2.8.3 | Unlicense OR MIT | https://github.com/BurntSushi/memchr |
| proc-macro2 | 1.0.107 | MIT OR Apache-2.0 | https://github.com/dtolnay/proc-macro2 |
| quote | 1.0.47 | MIT OR Apache-2.0 | https://github.com/dtolnay/quote |
| serde | 1.0.229 | MIT OR Apache-2.0 | https://github.com/serde-rs/serde |
| serde_core | 1.0.229 | MIT OR Apache-2.0 | https://github.com/serde-rs/serde |
| serde_derive | 1.0.229 | MIT OR Apache-2.0 | https://github.com/serde-rs/serde |
| serde_json | 1.0.151 | MIT OR Apache-2.0 | https://github.com/serde-rs/json |
| syn | 3.0.5 | MIT OR Apache-2.0 | https://github.com/dtolnay/syn |
| unicode-ident | 1.0.24 | (MIT OR Apache-2.0) AND Unicode-3.0 | https://github.com/dtolnay/unicode-ident |
| zmij | 1.0.23 | MIT | https://github.com/dtolnay/zmij |

To update, change the pinned dependency in `plugins/official/cppSupport/Cargo.toml`, regenerate
its lockfile after reviewing the new graph, run `cargo vendor --locked --offline --manifest-path
plugins/official/cppSupport/Cargo.toml lib/cargo` with the exact new crates available locally,
remove superseded snapshots, update this table and `NOTICE`, then run the full test, lint, and
public audit scripts. Keep dependency changes in their own reviewable commit when practical.
