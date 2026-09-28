//! Persistent numeric editor preferences shared by Settings and the plugin property surface.

use std::ffi::{CStr, c_char};
use std::io::Write;
use std::path::PathBuf;
use std::sync::Mutex;

static preferenceLock: Mutex<()> = Mutex::new(());

fn preferencePath() -> Option<PathBuf> {
    Some(PathBuf::from(std::env::var_os("HOME")?).join(".kinetic/editorSettings.json"))
}

fn readValues(path: &std::path::Path) -> Result<serde_json::Map<String, serde_json::Value>, ()> {
    match std::fs::read(path) {
        Ok(bytes) => serde_json::from_slice(&bytes).map_err(|_| ()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            Ok(serde_json::Map::default())
        }
        Err(_) => Err(()),
    }
}

/// Read a saved preference. Missing or invalid values leave the caller's default unchanged.
///
/// # Safety
/// Non-null pointers must reference a terminated UTF-8 key and writable output respectively.
#[allow(unsafe_code, reason = "validated C ABI pointers")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn kineticPreferenceRead(key: *const c_char, value: *mut f64) -> bool {
    if key.is_null() || value.is_null() {
        return false;
    }
    let Ok(key) = (unsafe { CStr::from_ptr(key) }).to_str() else {
        return false;
    };
    let Some(path) = preferencePath() else {
        return false;
    };
    let Ok(values) = readValues(&path) else {
        return false;
    };
    let Some(number) = values.get(key).and_then(serde_json::Value::as_f64) else {
        return false;
    };
    unsafe {
        *value = number;
    }
    true
}

/// Atomically save one preference without replacing unrelated keys or malformed files.
///
/// # Safety
/// A non-null key must reference a terminated UTF-8 string valid for the call.
#[allow(unsafe_code, reason = "validated C ABI string pointer")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn kineticPreferenceWrite(key: *const c_char, value: f64) -> bool {
    if key.is_null() || !value.is_finite() {
        return false;
    }
    let Ok(key) = (unsafe { CStr::from_ptr(key) }).to_str() else {
        return false;
    };
    if key.is_empty()
        || key.len() > 128
        || !key.chars().all(|c| c.is_ascii_alphanumeric() || c == '.')
    {
        return false;
    }
    let Some(path) = preferencePath() else {
        return false;
    };
    let Ok(_guard) = preferenceLock.lock() else {
        return false;
    };
    writeValue(&path, key, value)
}

fn writeValue(path: &std::path::Path, key: &str, value: f64) -> bool {
    let Ok(mut values) = readValues(path) else {
        return false;
    };
    values.insert(key.to_owned(), serde_json::json!(value));
    let Some(parent) = path.parent() else {
        return false;
    };
    if std::fs::create_dir_all(parent).is_err() {
        return false;
    }
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    let temporary = parent.join(format!(
        ".editorSettings.{}.{stamp}.tmp",
        std::process::id()
    ));
    let Ok(bytes) = serde_json::to_vec_pretty(&values) else {
        return false;
    };
    let Ok(mut file) = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&temporary)
    else {
        return false;
    };
    let saved = file
        .write_all(&bytes)
        .and_then(|()| file.sync_all())
        .and_then(|()| std::fs::rename(&temporary, path))
        .is_ok();
    if !saved {
        let _ = std::fs::remove_file(&temporary);
    }
    saved
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundTripAndPreserveMalformedPreferences() {
        let stamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let directory =
            std::env::temp_dir().join(format!("kineticPreferences-{}-{stamp}", std::process::id()));
        let path = directory.join("settings.json");
        assert!(writeValue(&path, "editor.text.fontSize", 15.0));
        assert!(writeValue(&path, "interface.motion.enabled", 0.0));
        let values = readValues(&path).unwrap();
        assert_eq!(values["editor.text.fontSize"], 15.0);
        assert_eq!(values["interface.motion.enabled"], 0.0);
        std::fs::write(&path, b"invalid json").unwrap();
        assert!(!writeValue(&path, "editor.text.fontSize", 17.0));
        assert_eq!(std::fs::read(&path).unwrap(), b"invalid json");
        std::fs::remove_file(path).unwrap();
        std::fs::remove_dir(directory).unwrap();
    }
}
