//! Filesystem operations for project folders. The UI keeps presentation state only.

use std::ffi::{CStr, c_char};
use std::path::Path;

use serde_json::{Value, json};

#[allow(
    unsafe_code,
    reason = "reading a C string is required at the ABI boundary"
)]
fn pathFromC(path: *const c_char) -> Option<String> {
    if path.is_null() {
        return None;
    }
    // SAFETY: The C ABI requires a non-null, NUL-terminated string from the caller.
    unsafe { CStr::from_ptr(path) }
        .to_str()
        .ok()
        .map(str::to_owned)
}

fn directoryEntries(path: &Path) -> Option<Vec<Value>> {
    let mut entries = std::fs::read_dir(path)
        .ok()?
        .filter_map(Result::ok)
        .filter_map(|entry| {
            let name = entry.file_name().into_string().ok()?;
            let path = entry.path().into_os_string().into_string().ok()?;
            let directory = entry.metadata().ok()?.is_dir();
            Some((name, path, directory))
        })
        .collect::<Vec<_>>();
    entries.sort_by(|left, right| {
        right
            .2
            .cmp(&left.2)
            .then_with(|| left.0.to_lowercase().cmp(&right.0.to_lowercase()))
            .then_with(|| left.0.cmp(&right.0))
    });
    Some(
        entries
            .into_iter()
            .map(|(name, path, directory)| {
                json!({"name": name, "path": path, "directory": directory})
            })
            .collect(),
    )
}

#[allow(unsafe_code, reason = "the stable C ABI requires an unmangled export")]
#[unsafe(no_mangle)]
pub extern "C" fn kineticWorkspaceIsFolder(path: *const c_char) -> bool {
    pathFromC(path).is_some_and(|path| Path::new(&path).is_dir())
}

/// Returns the required UTF-8 JSON byte count, or zero on failure.
/// A second call copies the complete array only if capacity is sufficient.
#[allow(
    unsafe_code,
    reason = "the stable C ABI requires an unmangled export and buffer write"
)]
#[unsafe(no_mangle)]
pub extern "C" fn kineticWorkspaceListDirectory(
    path: *const c_char,
    output: *mut u8,
    capacity: u64,
) -> u64 {
    let Some(path) = pathFromC(path) else {
        return 0;
    };
    let Some(entries) = directoryEntries(Path::new(&path)) else {
        return 0;
    };
    let Ok(bytes) = serde_json::to_vec(&entries) else {
        return 0;
    };
    let required = bytes.len() as u64;
    if !output.is_null() && capacity >= required {
        // SAFETY: The caller promises output points to a writable buffer of capacity bytes.
        unsafe { std::ptr::copy_nonoverlapping(bytes.as_ptr(), output, bytes.len()) };
    }
    required
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;

    #[test]
    fn listIncludesHiddenFilesAndFoldersFirst() {
        let nonce = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let root =
            std::env::temp_dir().join(format!("kinetic-workspace-{}-{nonce}", std::process::id()));
        std::fs::create_dir(&root).unwrap();
        std::fs::create_dir(root.join(".hiddenDir")).unwrap();
        std::fs::write(root.join(".hiddenFile"), b"").unwrap();
        let path = CString::new(root.to_str().unwrap()).unwrap();
        assert!(kineticWorkspaceIsFolder(path.as_ptr()));
        let size = kineticWorkspaceListDirectory(path.as_ptr(), std::ptr::null_mut(), 0);
        let mut bytes = vec![0; usize::try_from(size).unwrap()];
        assert_eq!(
            kineticWorkspaceListDirectory(path.as_ptr(), bytes.as_mut_ptr(), size),
            size
        );
        let entries: Value = serde_json::from_slice(&bytes).unwrap();
        assert_eq!(entries[0]["name"], ".hiddenDir");
        assert_eq!(entries[0]["directory"], true);
        assert_eq!(entries[1]["name"], ".hiddenFile");
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn rejectsMissingFolderAndShortBuffer() {
        let missing = CString::new("/this-folder-does-not-exist-kinetic").unwrap();
        assert!(!kineticWorkspaceIsFolder(missing.as_ptr()));
        assert_eq!(
            kineticWorkspaceListDirectory(missing.as_ptr(), std::ptr::null_mut(), 0),
            0
        );
        let root = CString::new(std::env::temp_dir().to_str().unwrap()).unwrap();
        let mut sentinel = [9_u8; 1];
        assert!(kineticWorkspaceListDirectory(root.as_ptr(), sentinel.as_mut_ptr(), 1) > 1);
        assert_eq!(sentinel, [9]);
    }
}
