use std::path::PathBuf;
use std::process::Command;

fn bundledRoot() -> Option<PathBuf> {
    let executable = std::env::current_exe().ok()?;
    executable
        .ancestors()
        .find(|path| path.file_name().is_some_and(|name| name == "Contents"))
        .map(|contents| contents.join("Resources/tools/llvm"))
}

pub fn command(name: &str) -> Command {
    let overrideKey = if name == "clangd" {
        "KINETIC_CLANGD"
    } else {
        "KINETIC_CLANG_FORMAT"
    };
    if let Some(path) = std::env::var_os(overrideKey).filter(|path| !path.is_empty()) {
        return Command::new(path);
    }
    if let Some(root) = bundledRoot() {
        let executable = root.join("bin").join(name);
        if executable.is_file() {
            let mut command = Command::new(executable);
            if name == "clangd"
                && let Ok(manifest) = std::fs::read(root.join("manifest.json"))
                && let Ok(manifest) = serde_json::from_slice::<serde_json::Value>(&manifest)
                && let Some(version) = manifest["resourceVersion"].as_str()
                && version
                    .chars()
                    .all(|character| character.is_ascii_digit() || character == '.')
            {
                command.arg(format!(
                    "--resource-dir={}",
                    root.join("lib/clang").join(version).display()
                ));
            }
            return command;
        }
    }
    Command::new(name)
}
