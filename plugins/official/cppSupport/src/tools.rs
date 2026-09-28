#[path = "../../../../src/Rust/backend/src/toolDiscovery.rs"]
mod discovery;

use std::process::Command;

pub fn command(name: &str) -> Command {
    Command::new(discovery::discover(name).unwrap_or_else(|| name.into()))
}
