//! Document-word completion and portable editor settings.

#![allow(non_snake_case)]

use std::collections::HashMap;
use std::env;
use std::fmt::Write as _;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::os::unix::fs::PermissionsExt;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

#[repr(C)]
#[derive(Clone, Copy)]
pub struct KineticCompletionItem {
    pub label: [u8; 96],
    pub insertText: [u8; 96],
    pub kind: u32,
}

impl Default for KineticCompletionItem {
    fn default() -> Self {
        Self {
            label: [0; 96],
            insertText: [0; 96],
            kind: 0,
        }
    }
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct KineticCompletionConfig {
    pub enabled: bool,
    pub minPrefix: u32,
    pub maxResults: u32,
}

impl Default for KineticCompletionConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            minPrefix: 2,
            maxResults: 8,
        }
    }
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct KineticIndentationConfig {
    pub tabWidth: u32,
    pub insertTabs: bool,
    pub autoIndent: bool,
}

impl Default for KineticIndentationConfig {
    fn default() -> Self {
        Self {
            tabWidth: 4,
            insertTabs: false,
            autoIndent: true,
        }
    }
}

fn isWord(character: char) -> bool {
    character == '_' || character.is_alphanumeric()
}

fn caretByte(text: &str, caretUtf16: usize) -> Option<usize> {
    let mut utf16 = 0;
    for (byte, character) in text.char_indices() {
        if utf16 == caretUtf16 {
            return Some(byte);
        }
        utf16 += character.len_utf16();
        if utf16 > caretUtf16 {
            return None;
        }
    }
    (utf16 == caretUtf16).then_some(text.len())
}

fn prefixAtCaret(text: &str, caretUtf16: usize) -> Option<(usize, String)> {
    let end = caretByte(text, caretUtf16)?;
    let mut start = end;
    for (offset, character) in text[..end].char_indices().rev() {
        if !isWord(character) {
            break;
        }
        start = offset;
    }
    let prefix = &text[start..end];
    if prefix.len() > 95 {
        return None;
    }
    Some((text[..start].encode_utf16().count(), prefix.to_string()))
}

fn collect(
    text: &str,
    caretUtf16: usize,
    minPrefix: usize,
    maximum: usize,
) -> (usize, Vec<String>) {
    let Some((start, prefix)) = prefixAtCaret(text, caretUtf16) else {
        return (caretUtf16, Vec::new());
    };
    if prefix.chars().count() < minPrefix || prefix.is_empty() {
        return (start, Vec::new());
    }
    let foldedPrefix = prefix.to_lowercase();
    let mut counts = HashMap::<String, usize>::new();
    for word in text.split(|character: char| !isWord(character)) {
        if word.len() <= prefix.len() || word.len() > 95 {
            continue;
        }
        if word.to_lowercase().starts_with(&foldedPrefix) {
            *counts.entry(word.to_string()).or_default() += 1;
        }
    }
    let mut ranked: Vec<_> = counts.into_iter().collect();
    ranked.sort_by(|left, right| right.1.cmp(&left.1).then_with(|| left.0.cmp(&right.0)));
    (
        start,
        ranked
            .into_iter()
            .take(maximum)
            .map(|item| item.0)
            .collect(),
    )
}

fn copyString(value: &str, target: &mut [u8; 96]) {
    let bytes = value.as_bytes();
    target[..bytes.len()].copy_from_slice(bytes);
}

#[allow(unsafe_code, reason = "the editor uses the stable C ABI")]
#[unsafe(no_mangle)]
pub extern "C" fn kineticCompletionCollect(
    bytes: *const u8,
    length: u64,
    caretUtf16: u64,
    minPrefix: u32,
    items: *mut KineticCompletionItem,
    capacity: u32,
    prefixStartUtf16: *mut u64,
) -> u32 {
    if bytes.is_null()
        || items.is_null()
        || prefixStartUtf16.is_null()
        || length > 16 * 1024 * 1024
        || capacity > 64
    {
        return 0;
    }
    let (Ok(length), Ok(caretUtf16)) = (usize::try_from(length), usize::try_from(caretUtf16))
    else {
        return 0;
    };
    // SAFETY: The caller provides readable document bytes and writable bounded output buffers.
    let source = unsafe { std::slice::from_raw_parts(bytes, length) };
    let Ok(text) = std::str::from_utf8(source) else {
        return 0;
    };
    let (start, suggestions) = collect(text, caretUtf16, minPrefix as usize, capacity as usize);
    // SAFETY: Both output pointers are validated above; capacity is capped at 64.
    unsafe {
        *prefixStartUtf16 = start as u64;
        let output = std::slice::from_raw_parts_mut(items, capacity as usize);
        for (slot, suggestion) in output.iter_mut().zip(suggestions.iter()) {
            *slot = KineticCompletionItem::default();
            copyString(suggestion, &mut slot.label);
            copyString(suggestion, &mut slot.insertText);
            slot.kind = 1;
        }
    }
    u32::try_from(suggestions.len()).unwrap_or(0)
}

fn configurationPath() -> Option<PathBuf> {
    Some(PathBuf::from(env::var_os("HOME")?).join(".kinetic/config.toml"))
}

fn parseConfiguration(text: &str) -> Result<KineticCompletionConfig, ()> {
    let mut config = KineticCompletionConfig::default();
    let mut inAutocomplete = false;
    let mut seen = [false; 3];
    for raw in text.lines() {
        let line = raw.split('#').next().unwrap_or("").trim();
        if line.is_empty() {
            continue;
        }
        if line.starts_with('[') {
            inAutocomplete = line == "[autocomplete]";
            continue;
        }
        if !inAutocomplete {
            continue;
        }
        let (key, value) = line.split_once('=').ok_or(())?;
        match (key.trim(), value.trim()) {
            ("enabled", value) if !seen[0] => {
                config.enabled = match value {
                    "true" => true,
                    "false" => false,
                    _ => return Err(()),
                };
                seen[0] = true;
            }
            ("minPrefix", value) if !seen[1] => {
                config.minPrefix = value.parse().map_err(|_| ())?;
                if !(1..=8).contains(&config.minPrefix) {
                    return Err(());
                }
                seen[1] = true;
            }
            ("maxResults", value) if !seen[2] => {
                config.maxResults = value.parse().map_err(|_| ())?;
                if !(1..=32).contains(&config.maxResults) {
                    return Err(());
                }
                seen[2] = true;
            }
            _ => return Err(()),
        }
    }
    Ok(config)
}

fn updateConfiguration(text: &str, config: KineticCompletionConfig) -> Result<String, ()> {
    parseConfiguration(text)?;
    let mut output = String::new();
    let mut inAutocomplete = false;
    let mut found = false;
    let mut seen = [false; 3];
    for raw in text.split_inclusive('\n') {
        let line = raw.trim_end_matches(['\r', '\n']);
        let trimmed = line.trim();
        if trimmed.starts_with('[') {
            if inAutocomplete {
                appendMissing(&mut output, config, seen);
                inAutocomplete = false;
            }
            if trimmed == "[autocomplete]" {
                inAutocomplete = true;
                found = true;
                seen = [false; 3];
            }
        }
        if inAutocomplete && !trimmed.starts_with('[') {
            if let Some((key, _)) = line.split_once('=') {
                let index = match key.trim() {
                    "enabled" => Some(0),
                    "minPrefix" => Some(1),
                    "maxResults" => Some(2),
                    _ => None,
                };
                if let Some(index) = index {
                    seen[index] = true;
                    let comment = line.find('#').map_or("", |offset| &line[offset..]);
                    let value = match index {
                        0 => config.enabled.to_string(),
                        1 => config.minPrefix.to_string(),
                        _ => config.maxResults.to_string(),
                    };
                    let _ = write!(output, "{} = {value}", key.trim());
                    if !comment.is_empty() {
                        output.push(' ');
                        output.push_str(comment);
                    }
                    if raw.ends_with('\n') {
                        output.push('\n');
                    }
                    continue;
                }
            }
        }
        output.push_str(raw);
    }
    if inAutocomplete {
        if !output.ends_with('\n') {
            output.push('\n');
        }
        appendMissing(&mut output, config, seen);
    }
    if !found {
        if !output.is_empty() && !output.ends_with('\n') {
            output.push('\n');
        }
        if !output.is_empty() {
            output.push('\n');
        }
        output.push_str("[autocomplete]\n");
        appendMissing(&mut output, config, [false; 3]);
    }
    Ok(output)
}

fn appendMissing(output: &mut String, config: KineticCompletionConfig, seen: [bool; 3]) {
    if !seen[0] {
        let _ = writeln!(output, "enabled = {}", config.enabled);
    }
    if !seen[1] {
        let _ = writeln!(output, "minPrefix = {}", config.minPrefix);
    }
    if !seen[2] {
        let _ = writeln!(output, "maxResults = {}", config.maxResults);
    }
}

fn parseIndentation(text: &str) -> Result<KineticIndentationConfig, ()> {
    let mut config = KineticIndentationConfig::default();
    let mut inEditor = false;
    let mut seen = [false; 3];
    for raw in text.lines() {
        let line = raw.split('#').next().unwrap_or("").trim();
        if line.starts_with('[') {
            inEditor = line == "[editor]";
            continue;
        }
        if !inEditor || line.is_empty() {
            continue;
        }
        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        let value = value.trim();
        match key.trim() {
            "tabWidth" if !seen[0] => {
                config.tabWidth = value.parse().map_err(|_| ())?;
                if !(1..=16).contains(&config.tabWidth) {
                    return Err(());
                }
                seen[0] = true;
            }
            "insertTabs" if !seen[1] => {
                config.insertTabs = value.parse().map_err(|_| ())?;
                seen[1] = true;
            }
            "autoIndent" if !seen[2] => {
                config.autoIndent = value.parse().map_err(|_| ())?;
                seen[2] = true;
            }
            "tabWidth" | "insertTabs" | "autoIndent" => return Err(()),
            _ => {}
        }
    }
    Ok(config)
}

fn appendMissingIndentation(
    output: &mut String,
    config: KineticIndentationConfig,
    seen: [bool; 3],
) {
    if !seen[0] {
        let _ = writeln!(output, "tabWidth = {}", config.tabWidth);
    }
    if !seen[1] {
        let _ = writeln!(output, "insertTabs = {}", config.insertTabs);
    }
    if !seen[2] {
        let _ = writeln!(output, "autoIndent = {}", config.autoIndent);
    }
}

fn updateIndentation(text: &str, config: KineticIndentationConfig) -> Result<String, ()> {
    parseIndentation(text)?;
    let mut output = String::new();
    let mut inEditor = false;
    let mut found = false;
    let mut seen = [false; 3];
    for raw in text.split_inclusive('\n') {
        let line = raw.trim_end_matches(['\r', '\n']);
        let trimmed = line.trim();
        if trimmed.starts_with('[') {
            if inEditor {
                appendMissingIndentation(&mut output, config, seen);
                inEditor = false;
            }
            if trimmed == "[editor]" {
                inEditor = true;
                found = true;
                seen = [false; 3];
            }
        }
        if inEditor
            && !trimmed.starts_with('[')
            && let Some((key, _)) = line.split_once('=')
        {
            let index = match key.trim() {
                "tabWidth" => Some(0),
                "insertTabs" => Some(1),
                "autoIndent" => Some(2),
                _ => None,
            };
            if let Some(index) = index {
                seen[index] = true;
                let comment = line.find('#').map_or("", |offset| &line[offset..]);
                let value = match index {
                    0 => config.tabWidth.to_string(),
                    1 => config.insertTabs.to_string(),
                    _ => config.autoIndent.to_string(),
                };
                let _ = write!(output, "{} = {value}", key.trim());
                if !comment.is_empty() {
                    output.push(' ');
                    output.push_str(comment);
                }
                if raw.ends_with('\n') {
                    output.push('\n');
                }
                continue;
            }
        }
        output.push_str(raw);
    }
    if inEditor {
        if !output.ends_with('\n') {
            output.push('\n');
        }
        appendMissingIndentation(&mut output, config, seen);
    }
    if !found {
        if !output.is_empty() && !output.ends_with('\n') {
            output.push('\n');
        }
        if !output.is_empty() {
            output.push('\n');
        }
        output.push_str("[editor]\n");
        appendMissingIndentation(&mut output, config, [false; 3]);
    }
    Ok(output)
}

#[allow(unsafe_code, reason = "the editor uses the stable C ABI")]
#[unsafe(no_mangle)]
pub extern "C" fn kineticCompletionReadConfig(output: *mut KineticCompletionConfig) -> i32 {
    if output.is_null() {
        return -1;
    }
    let Some(path) = configurationPath() else {
        return -1;
    };
    let config = if path.exists() {
        let Ok(bytes) = fs::read(&path) else {
            return -1;
        };
        if bytes.len() > 65_536 {
            return -1;
        }
        let Ok(text) = String::from_utf8(bytes) else {
            return -1;
        };
        let Ok(parsed) = parseConfiguration(&text) else {
            return -1;
        };
        parsed
    } else {
        KineticCompletionConfig::default()
    };
    // SAFETY: The caller provides a writable config structure.
    unsafe {
        *output = config;
    }
    0
}

#[allow(unsafe_code, reason = "the editor uses the stable C ABI")]
#[unsafe(no_mangle)]
pub extern "C" fn kineticCompletionWriteConfig(input: *const KineticCompletionConfig) -> i32 {
    if input.is_null() {
        return -1;
    }
    // SAFETY: The caller provides a readable config structure.
    let config = unsafe { *input };
    if !(1..=8).contains(&config.minPrefix) || !(1..=32).contains(&config.maxResults) {
        return -1;
    }
    persistConfiguration(|previous| updateConfiguration(previous, config))
}

fn persistConfiguration(update: impl FnOnce(&str) -> Result<String, ()>) -> i32 {
    let Some(path) = configurationPath() else {
        return -1;
    };
    let Some(parent) = path.parent() else {
        return -1;
    };
    if fs::create_dir_all(parent).is_err() {
        return -1;
    }
    let metadata = match fs::symlink_metadata(&path) {
        Ok(metadata) if metadata.file_type().is_file() => Some(metadata),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => None,
        Ok(_) | Err(_) => return -1,
    };
    let previous = if metadata.is_some() {
        let Ok(bytes) = fs::read(&path) else {
            return -1;
        };
        if bytes.len() > 65_536 {
            return -1;
        }
        let Ok(text) = String::from_utf8(bytes) else {
            return -1;
        };
        text
    } else {
        String::new()
    };
    let Ok(updated) = update(&previous) else {
        return -1;
    };
    let stamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |time| time.as_nanos());
    let temporary = parent.join(format!(".config.toml.{}.{stamp}.tmp", std::process::id()));
    let result = (|| -> std::io::Result<()> {
        let mut file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&temporary)?;
        let permissions = metadata.map_or(0o600, |value| value.permissions().mode() & 0o777);
        file.set_permissions(fs::Permissions::from_mode(permissions))?;
        file.write_all(updated.as_bytes())?;
        file.sync_all()?;
        fs::rename(&temporary, &path)
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temporary);
        return -1;
    }
    0
}

#[allow(unsafe_code, reason = "the editor uses the stable C ABI")]
#[unsafe(no_mangle)]
pub extern "C" fn kineticIndentationReadConfig(output: *mut KineticIndentationConfig) -> i32 {
    if output.is_null() {
        return -1;
    }
    let Some(path) = configurationPath() else {
        return -1;
    };
    let config = if path.exists() {
        let Ok(bytes) = fs::read(&path) else {
            return -1;
        };
        if bytes.len() > 65_536 {
            return -1;
        }
        let Ok(text) = String::from_utf8(bytes) else {
            return -1;
        };
        let Ok(config) = parseIndentation(&text) else {
            return -1;
        };
        config
    } else {
        KineticIndentationConfig::default()
    };
    // SAFETY: The caller provides a writable config structure.
    unsafe {
        *output = config;
    }
    0
}

#[allow(unsafe_code, reason = "the editor uses the stable C ABI")]
#[unsafe(no_mangle)]
pub extern "C" fn kineticIndentationWriteConfig(input: *const KineticIndentationConfig) -> i32 {
    if input.is_null() {
        return -1;
    }
    // SAFETY: The caller provides a readable config structure.
    let config = unsafe { *input };
    if !(1..=16).contains(&config.tabWidth) {
        return -1;
    }
    persistConfiguration(|previous| updateIndentation(previous, config))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ranksDocumentWordsAndRejectsSplitSurrogate() {
        let text = "hello helper helloWorld helper helper he";
        let (_, values) = collect(text, text.encode_utf16().count(), 2, 8);
        assert_eq!(values, ["helper", "hello", "helloWorld"]);
        assert_eq!(prefixAtCaret("😀he", 1), None);
    }

    #[test]
    fn parsesAutocompleteSettingsWithoutChangingOtherTables() {
        let config = parseConfiguration("[plugins]\nenabled = true\n[autocomplete]\nenabled = false\nminPrefix = 3\nmaxResults = 12\n").unwrap();
        assert!(!config.enabled);
        assert_eq!(config.minPrefix, 3);
        assert_eq!(config.maxResults, 12);
        assert!(parseConfiguration("[autocomplete]\nmaxResults = 0").is_err());
    }

    #[test]
    fn updatesOnlyAutocompleteValues() {
        let original = "[plugins]\nenabled = true\n\n[autocomplete]\n# Keep this note\nenabled = false # toggle\nminPrefix = 3\n\n[search]\nshowButton = true\n";
        let updated = updateConfiguration(original, KineticCompletionConfig::default()).unwrap();
        assert!(updated.contains("[plugins]\nenabled = true"));
        assert!(updated.contains("# Keep this note\nenabled = true # toggle"));
        assert!(updated.contains("minPrefix = 2\n\nmaxResults = 8\n[search]"));
        assert!(updated.ends_with("[search]\nshowButton = true\n"));
    }

    #[test]
    fn indentationSettingsKeepOtherEditorValues() {
        let original = "[editor]\nfontSize = 13\ntabWidth = 2 # style\nautoIndent = true\n\n[search]\nshowButton = true\n";
        let config = KineticIndentationConfig {
            tabWidth: 4,
            insertTabs: true,
            autoIndent: false,
        };
        let updated = updateIndentation(original, config).unwrap();
        assert!(updated.contains("fontSize = 13"));
        assert!(updated.contains("tabWidth = 4 # style"));
        assert!(updated.contains("insertTabs = true"));
        assert!(updated.contains("autoIndent = false"));
        assert!(updated.contains("[search]\nshowButton = true"));
        assert_eq!(parseIndentation(&updated).unwrap().tabWidth, 4);
    }
}
