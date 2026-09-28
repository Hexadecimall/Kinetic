use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

pub fn privateRoot() -> Option<PathBuf> {
    std::env::var_os("KINETIC_TOOLS_DIR")
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
        .or_else(|| std::env::var_os("HOME").map(|home| PathBuf::from(home).join(".kinetic/tools")))
}

pub fn candidates(name: &str) -> Vec<PathBuf> {
    let mut paths = Vec::new();
    let key = if name == "clangd" {
        "KINETIC_CLANGD"
    } else {
        "KINETIC_CLANG_FORMAT"
    };
    if let Some(path) = std::env::var_os(key).filter(|p| !p.is_empty()) {
        paths.push(PathBuf::from(path));
    }
    if let Some(root) = privateRoot() {
        paths.push(root.join(name).join("bin").join(name));
    }
    if let Some(path) = std::env::var_os("KINETIC_TOOL_SEARCH_PATH") {
        paths.extend(
            std::env::split_paths(&path)
                .filter(|p| p.is_absolute())
                .map(|p| p.join(name)),
        );
        return paths;
    }
    if let Some(path) = std::env::var_os("PATH") {
        paths.extend(
            std::env::split_paths(&path)
                .filter(|p| p.is_absolute())
                .map(|p| p.join(name)),
        );
    }
    for root in [
        "/opt/homebrew/opt/llvm/bin",
        "/opt/homebrew/opt/llvm@23/bin",
        "/opt/homebrew/opt/llvm@22/bin",
        "/opt/homebrew/opt/llvm@21/bin",
        "/usr/local/opt/llvm/bin",
        "/opt/local/bin",
        "/usr/local/bin",
        "/usr/bin",
    ] {
        paths.push(PathBuf::from(root).join(name));
    }
    paths
}

pub fn usable(path: &std::path::Path) -> bool {
    let Ok(mut child) = Command::new(path)
        .arg("--version")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
    else {
        return false;
    };
    let start = Instant::now();
    loop {
        match child.try_wait() {
            Ok(Some(status)) => return status.success(),
            Ok(None) if start.elapsed() < Duration::from_secs(3) => {
                std::thread::sleep(Duration::from_millis(20));
            }
            _ => {
                let _ = child.kill();
                let _ = child.wait();
                return false;
            }
        }
    }
}

pub fn discover(name: &str) -> Option<PathBuf> {
    candidates(name)
        .into_iter()
        .find(|p| p.is_file() && usable(p))
}
