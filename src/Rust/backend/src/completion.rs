//! Document-word completion and its portable dotfile settings.

#![allow(non_snake_case)]

use std::collections::HashMap;
use std::env;
use std::fs;
use std::path::PathBuf;

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
}
