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
            minPrefix: 1,
            maxResults: 24,
        }
    }
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct KineticIndentationConfig {
    pub tabWidth: u32,
    pub insertTabs: bool,
    pub autoIndent: bool,
    pub indentUnitNavigation: bool,
    pub showIndentGuides: bool,
}

impl Default for KineticIndentationConfig {
    fn default() -> Self {
        Self {
            tabWidth: 4,
            insertTabs: false,
            autoIndent: true,
            indentUnitNavigation: true,
            showIndentGuides: true,
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

fn completionContext(text: &str, prefixStartUtf16: usize, cFamily: bool) -> u32 {
    let Some(start) = caretByte(text, prefixStartUtf16) else {
        return 0;
    };
    let before = &text[..start];
    let member = before.ends_with('.') || before.ends_with("->") || before.ends_with("::");
    let mut context = u32::from(member);
    if !cFamily {
        return context;
    }
    let line = before.rsplit('\n').next().unwrap_or("").trim_start();
    let directive = ["#include", "#import"].into_iter().find_map(|name| {
        let rest = line.strip_prefix(name)?;
        rest.chars()
            .next()
            .is_some_and(|character| character.is_whitespace() || matches!(character, '<' | '"'))
            .then_some(rest)
    });
    if let Some(directive) = directive {
        let insideAngle = directive
            .split_once('<')
            .is_some_and(|(_, rest)| !rest.contains('>'));
        let insideQuote = directive.bytes().filter(|&byte| byte == b'"').count() % 2 == 1;
        if insideAngle || insideQuote {
            context |= 2;
        }
    }
    context
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

fn matchScore(query: &str, candidate: &str) -> i32 {
    if query.is_empty() {
        return 0;
    }
    let query = query.to_lowercase();
    let candidate = candidate.to_lowercase();
    if candidate.starts_with(&query) {
        let extraCharacters = candidate.chars().count() - query.chars().count();
        return 1000 - i32::try_from(extraCharacters.min(500)).unwrap_or(500);
    }
    let mut remaining = query.chars();
    let mut expected = remaining.next();
    let mut score = 0;
    let mut previousMatch = false;
    let mut previous = ' ';
    for character in candidate.chars() {
        if Some(character) == expected {
            score += if previousMatch { 24 } else { 8 };
            if !previous.is_alphanumeric() || (previous.is_lowercase() && character.is_uppercase())
            {
                score += 16;
            }
            expected = remaining.next();
            previousMatch = true;
            if expected.is_none() {
                return score;
            }
        } else {
            previousMatch = false;
        }
        previous = character;
    }
    -1
}

fn expandSnippet(source: &str) -> (String, usize) {
    let characters: Vec<char> = source.chars().collect();
    let mut output = String::new();
    let mut firstStop: Option<(u32, usize)> = None;
    let mut finalStop = None;
    let mut index = 0;
    while index < characters.len() {
        if characters[index] == '\\'
            && index + 1 < characters.len()
            && matches!(characters[index + 1], '$' | '}' | '\\')
        {
            output.push(characters[index + 1]);
            index += 2;
            continue;
        }
        if characters[index] == '$' {
            let mut digitStart = index + 1;
            let braced = characters.get(digitStart) == Some(&'{');
            if braced {
                digitStart += 1;
            }
            let mut digitEnd = digitStart;
            while characters.get(digitEnd).is_some_and(char::is_ascii_digit) {
                digitEnd += 1;
            }
            if digitEnd > digitStart {
                let number: String = characters[digitStart..digitEnd].iter().collect();
                if let Ok(number) = number.parse::<u32>() {
                    let offset = output.encode_utf16().count();
                    if number == 0 {
                        finalStop = Some(offset);
                    } else if firstStop.is_none_or(|(current, _)| number < current) {
                        firstStop = Some((number, offset));
                    }
                    if !braced {
                        index = digitEnd;
                        continue;
                    }
                    let mut end = digitEnd;
                    while end < characters.len() && characters[end] != '}' {
                        end += 1;
                    }
                    if end < characters.len() {
                        if characters.get(digitEnd) == Some(&':') {
                            output.extend(characters[digitEnd + 1..end].iter());
                        }
                        index = end + 1;
                        continue;
                    }
                }
            }
        }
        output.push(characters[index]);
        index += 1;
    }
    let caret = firstStop
        .map(|(_, offset)| offset)
        .or(finalStop)
        .unwrap_or_else(|| output.encode_utf16().count());
    (output, caret)
}

#[allow(unsafe_code, reason = "the editor uses the stable C ABI")]
#[unsafe(no_mangle)]
pub extern "C" fn kineticCompletionMatchScore(
    query: *const u8,
    queryLength: u64,
    candidate: *const u8,
    candidateLength: u64,
) -> i32 {
    if query.is_null() || candidate.is_null() || queryLength > 1024 || candidateLength > 4096 {
        return -1;
    }
    let (Ok(queryLength), Ok(candidateLength)) = (
        usize::try_from(queryLength),
        usize::try_from(candidateLength),
    ) else {
        return -1;
    };
    // SAFETY: The caller provides readable buffers for the declared bounded lengths.
    let query = unsafe { std::slice::from_raw_parts(query, queryLength) };
    let candidate = unsafe { std::slice::from_raw_parts(candidate, candidateLength) };
    match (std::str::from_utf8(query), std::str::from_utf8(candidate)) {
        (Ok(query), Ok(candidate)) => matchScore(query, candidate),
        _ => -1,
    }
}

#[allow(unsafe_code, reason = "the editor uses the stable C ABI")]
#[unsafe(no_mangle)]
pub extern "C" fn kineticCompletionExpandSnippet(
    source: *const u8,
    sourceLength: u64,
    output: *mut u8,
    capacity: u64,
    caretUtf16: *mut u64,
) -> u64 {
    if source.is_null() || caretUtf16.is_null() || sourceLength > 1024 * 1024 {
        return u64::MAX;
    }
    let Ok(sourceLength) = usize::try_from(sourceLength) else {
        return u64::MAX;
    };
    // SAFETY: The caller provides readable source bytes and a writable caret slot.
    let source = unsafe { std::slice::from_raw_parts(source, sourceLength) };
    let Ok(source) = std::str::from_utf8(source) else {
        return u64::MAX;
    };
    let (text, caret) = expandSnippet(source);
    // SAFETY: caretUtf16 was checked above.
    unsafe { *caretUtf16 = caret as u64 };
    if !output.is_null() && capacity >= text.len() as u64 {
        // SAFETY: The caller declares at least text.len() bytes of writable capacity.
        unsafe { std::ptr::copy_nonoverlapping(text.as_ptr(), output, text.len()) };
    }
    text.len() as u64
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

#[allow(unsafe_code, reason = "the editor uses the stable C ABI")]
#[unsafe(no_mangle)]
pub extern "C" fn kineticCompletionContext(
    bytes: *const u8,
    length: u64,
    prefixStartUtf16: u64,
    languageFlags: u32,
) -> u32 {
    if bytes.is_null() || length > 16 * 1024 * 1024 {
        return 0;
    }
    let (Ok(length), Ok(prefixStartUtf16)) =
        (usize::try_from(length), usize::try_from(prefixStartUtf16))
    else {
        return 0;
    };
    // SAFETY: The caller provides a readable document buffer for the declared bounded length.
    let source = unsafe { std::slice::from_raw_parts(bytes, length) };
    let Ok(text) = std::str::from_utf8(source) else {
        return 0;
    };
    completionContext(text, prefixStartUtf16, languageFlags & 1 != 0)
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
                if !(1..=128).contains(&config.maxResults) {
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
    let mut seen = [false; 5];
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
            "indentUnitNavigation" if !seen[3] => {
                config.indentUnitNavigation = value.parse().map_err(|_| ())?;
                seen[3] = true;
            }
            "showIndentGuides" if !seen[4] => {
                config.showIndentGuides = value.parse().map_err(|_| ())?;
                seen[4] = true;
            }
            "tabWidth"
            | "insertTabs"
            | "autoIndent"
            | "indentUnitNavigation"
            | "showIndentGuides" => return Err(()),
            _ => {}
        }
    }
    Ok(config)
}

fn appendMissingIndentation(
    output: &mut String,
    config: KineticIndentationConfig,
    seen: [bool; 5],
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
    if !seen[3] {
        let _ = writeln!(
            output,
            "indentUnitNavigation = {}",
            config.indentUnitNavigation
        );
    }
    if !seen[4] {
        let _ = writeln!(output, "showIndentGuides = {}", config.showIndentGuides);
    }
}

fn updateIndentation(text: &str, config: KineticIndentationConfig) -> Result<String, ()> {
    parseIndentation(text)?;
    let mut output = String::new();
    let mut inEditor = false;
    let mut found = false;
    let mut seen = [false; 5];
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
                seen = [false; 5];
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
                "indentUnitNavigation" => Some(3),
                "showIndentGuides" => Some(4),
                _ => None,
            };
            if let Some(index) = index {
                seen[index] = true;
                let comment = line.find('#').map_or("", |offset| &line[offset..]);
                let value = match index {
                    0 => config.tabWidth.to_string(),
                    1 => config.insertTabs.to_string(),
                    2 => config.autoIndent.to_string(),
                    3 => config.indentUnitNavigation.to_string(),
                    _ => config.showIndentGuides.to_string(),
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
        appendMissingIndentation(&mut output, config, [false; 5]);
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
    if !(1..=8).contains(&config.minPrefix) || !(1..=128).contains(&config.maxResults) {
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
    fn ranksPrefixAboveFuzzyAndRejectsUnrelated() {
        assert!(matchScore("vec", "vector") > matchScore("vec", "validateEntryCount"));
        assert_eq!(matchScore("zz", "vector"), -1);
    }

    #[test]
    fn expandsBasicLspTabstops() {
        assert_eq!(
            expandSnippet("call(${1:value}, $2)$0"),
            ("call(value, )".into(), 5)
        );
        assert_eq!(expandSnippet("foo\\$bar"), ("foo$bar".into(), 7));
    }

    #[test]
    fn ranksDocumentWordsAndRejectsSplitSurrogate() {
        let text = "hello helper helloWorld helper helper he";
        let (_, values) = collect(text, text.encode_utf16().count(), 2, 8);
        assert_eq!(values, ["helper", "hello", "helloWorld"]);
        assert_eq!(prefixAtCaret("😀he", 1), None);
    }

    #[test]
    fn detectsLanguageTriggersAtUtf16Boundaries() {
        for source in ["object.x", "std::x", "pointer->x"] {
            let (start, _) = prefixAtCaret(source, source.encode_utf16().count()).unwrap();
            assert_eq!(completionContext(source, start, false), 1);
        }
        let source = "😀\n#include <vector/v";
        let (start, _) = prefixAtCaret(source, source.encode_utf16().count()).unwrap();
        assert_eq!(completionContext(source, start, true), 2);
        assert_eq!(completionContext(source, start, false), 0);
        assert_eq!(completionContext("#include <vector>", 17, true), 0);
        assert_eq!(completionContext("😀", 1, true), 0);
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
        assert!(updated.contains("minPrefix = 1\n\nmaxResults = 24\n[search]"));
        assert!(updated.ends_with("[search]\nshowButton = true\n"));
    }

    #[test]
    fn indentationSettingsKeepOtherEditorValues() {
        let original = "[editor]\nfontSize = 13\ntabWidth = 2 # style\nautoIndent = true\n\n[search]\nshowButton = true\n";
        let config = KineticIndentationConfig {
            tabWidth: 4,
            insertTabs: true,
            autoIndent: false,
            indentUnitNavigation: false,
            showIndentGuides: false,
        };
        let updated = updateIndentation(original, config).unwrap();
        assert!(updated.contains("fontSize = 13"));
        assert!(updated.contains("tabWidth = 4 # style"));
        assert!(updated.contains("insertTabs = true"));
        assert!(updated.contains("autoIndent = false"));
        assert!(updated.contains("indentUnitNavigation = false"));
        assert!(updated.contains("showIndentGuides = false"));
        assert!(updated.contains("[search]\nshowButton = true"));
        assert_eq!(parseIndentation(&updated).unwrap().tabWidth, 4);
    }
}
