#![allow(non_snake_case)]

mod language;
mod lsp;

use std::ffi::{CString, c_char, c_void};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicPtr, AtomicU8, Ordering};
use std::sync::{Mutex, OnceLock};

use lsp::LanguageServer;

#[repr(C)]
pub struct SyntaxToken {
    startUtf16: u32,
    lengthUtf16: u32,
    kind: u32,
}

#[repr(C)]
pub struct Diagnostic {
    line: u32,
    columnUtf16: u32,
    lengthUtf16: u32,
    severity: u32,
    message: [c_char; 256],
}

#[repr(C)]
pub struct PanelRow {
    kind: u32,
    title: [c_char; 96],
    commandId: [c_char; 128],
}

#[repr(C)]
pub struct CompletionRow {
    label: [c_char; 96],
    insertText: [c_char; 96],
    detail: [c_char; 96],
}

#[repr(C)]
pub struct PluginApi {
    abiVersion: u32,
    structSize: u32,
    context: *mut c_void,
    setNumber: usize,
    getNumber: usize,
    registerCommand: unsafe extern "C" fn(
        *mut c_void,
        *const c_char,
        *const c_char,
        extern "C" fn(*mut c_void),
        *mut c_void,
    ) -> i32,
    subscribeEvent: unsafe extern "C" fn(
        *mut c_void,
        *const c_char,
        extern "C" fn(*mut c_void, *const c_char),
        *mut c_void,
    ) -> i32,
    copyDocumentUtf8: unsafe extern "C" fn(*mut c_void, *mut c_char, u64) -> u64,
    replaceSelectionUtf8: usize,
    setString: usize,
    copyString: usize,
    getSelection: unsafe extern "C" fn(*mut c_void, *mut u64, *mut u64) -> i32,
    setSelection: usize,
    replaceRangeUtf8: usize,
    registerShortcut: unsafe extern "C" fn(*mut c_void, *const c_char, *const c_char, u32) -> i32,
    registerFileMenuItem: usize,
    registerPanel: unsafe extern "C" fn(
        *mut c_void,
        *const c_char,
        *const c_char,
        extern "C" fn(*mut c_void, *mut PanelRow, u32) -> u32,
        *mut c_void,
    ) -> i32,
    registerOverlay: usize,
    registerFormatter: unsafe extern "C" fn(
        *mut c_void,
        *const c_char,
        extern "C" fn(*mut c_void, *const c_char, u64, *mut c_char, u64) -> u64,
        *mut c_void,
    ) -> i32,
    registerSyntaxProvider: unsafe extern "C" fn(
        *mut c_void,
        *const c_char,
        extern "C" fn(*mut c_void, *const c_char, u64, *mut u32, *mut SyntaxToken, u32) -> u32,
        *mut c_void,
    ) -> i32,
    copyActiveFilePath: unsafe extern "C" fn(*mut c_void, *mut c_char, u64) -> u64,
    copyWorkspacePath: unsafe extern "C" fn(*mut c_void, *mut c_char, u64) -> u64,
    publishDiagnostics:
        unsafe extern "C" fn(*mut c_void, *const c_char, *const Diagnostic, u32) -> i32,
    openLocation: unsafe extern "C" fn(*mut c_void, *const c_char, u32, u32) -> i32,
    registerCompletionProvider: unsafe extern "C" fn(
        *mut c_void,
        *const c_char,
        extern "C" fn(*mut c_void, *const c_char, u64, *mut CompletionRow, u32) -> u32,
        *mut c_void,
    ) -> i32,
}

#[repr(C)]
pub struct PluginDescriptor {
    abiVersion: u32,
    structSize: u32,
    pluginId: *const c_char,
    displayName: *const c_char,
    version: *const c_char,
    start: extern "C" fn(*const PluginApi) -> i32,
    stop: extern "C" fn(),
}

unsafe impl Sync for PluginDescriptor {}

static API: AtomicPtr<PluginApi> = AtomicPtr::new(std::ptr::null_mut());
static STATUS: AtomicU8 = AtomicU8::new(0);
static SERVER: OnceLock<Mutex<Option<LanguageServer>>> = OnceLock::new();
static FORMAT_CACHE: OnceLock<Mutex<Option<Vec<u8>>>> = OnceLock::new();

fn formatCache() -> &'static Mutex<Option<Vec<u8>>> {
    FORMAT_CACHE.get_or_init(|| Mutex::new(None))
}

fn server() -> &'static Mutex<Option<LanguageServer>> {
    SERVER.get_or_init(|| Mutex::new(None))
}

fn api() -> Option<&'static PluginApi> {
    // SAFETY: The host keeps the API table and plugin context alive until stop returns.
    unsafe { API.load(Ordering::Acquire).as_ref() }
}

fn copyHostString(
    copy: unsafe extern "C" fn(*mut c_void, *mut c_char, u64) -> u64,
) -> Option<String> {
    let api = api()?;
    // SAFETY: Calls use the host-owned context on the main thread.
    let length = unsafe { copy(api.context, std::ptr::null_mut(), 0) };
    if length == u64::MAX || length > 16 * 1024 * 1024 {
        return None;
    }
    let mut bytes = vec![0_u8; length as usize + 1];
    // SAFETY: The buffer is writable for length + 1 bytes.
    let received = unsafe { copy(api.context, bytes.as_mut_ptr().cast(), bytes.len() as u64) };
    if received != length {
        return None;
    }
    String::from_utf8(bytes[..length as usize].to_vec()).ok()
}

fn activeDocument() -> Option<(String, String)> {
    let api = api()?;
    let path = copyHostString(api.copyActiveFilePath)?;
    let text = copyHostString(api.copyDocumentUtf8)?;
    Some((path, text))
}

extern "C" fn documentEvent(_userData: *mut c_void, _eventName: *const c_char) {
    if let Some((path, text)) = activeDocument()
        && let Ok(guard) = server().lock()
        && let Some(server) = guard.as_ref()
    {
        server.updateDocument(path, text);
    }
}

fn positionAtCaret(text: &str, caret: u64) -> (u32, u32) {
    let mut remaining = caret;
    let mut line = 0_u32;
    let mut column = 0_u32;
    for character in text.chars() {
        if remaining == 0 {
            break;
        }
        let units = character.len_utf16() as u64;
        if remaining < units {
            break;
        }
        remaining -= units;
        if character == '\n' {
            line += 1;
            column = 0;
        } else {
            column += units as u32;
        }
    }
    (line, column)
}

extern "C" fn completeDocument(
    _userData: *mut c_void,
    prefix: *const c_char,
    prefixLength: u64,
    rows: *mut CompletionRow,
    capacity: u32,
) -> u32 {
    if prefix.is_null() || rows.is_null() || prefixLength > 95 || capacity > 32 {
        return 0;
    }
    // SAFETY: The host supplies prefixLength readable bytes and capacity writable rows.
    let bytes = unsafe { std::slice::from_raw_parts(prefix.cast::<u8>(), prefixLength as usize) };
    let Ok(prefix) = std::str::from_utf8(bytes) else {
        return 0;
    };
    let Some((path, text)) = activeDocument() else {
        return 0;
    };
    let Some(api) = api() else { return 0 };
    let mut caret = 0_u64;
    let mut selectionLength = 0_u64;
    // SAFETY: The host writes two u64 values.
    if unsafe { (api.getSelection)(api.context, &mut caret, &mut selectionLength) } != 0 {
        return 0;
    }
    let (line, column) = positionAtCaret(&text, caret);
    let Ok(guard) = server().lock() else { return 0 };
    let Some(server) = guard.as_ref() else {
        return 0;
    };
    let suggestions = server.requestCompletions(path, text, line, column, prefix.into());
    // SAFETY: The host allocates capacity rows for this callback.
    let output = unsafe { std::slice::from_raw_parts_mut(rows, capacity as usize) };
    let mut count = 0;
    for item in suggestions.iter().filter(|item| {
        item.label
            .to_lowercase()
            .starts_with(&prefix.to_lowercase())
            && item.insertText != prefix
    }) {
        if count >= output.len() {
            break;
        }
        output[count] = CompletionRow {
            label: [0; 96],
            insertText: [0; 96],
            detail: [0; 96],
        };
        writeField(&mut output[count].label, &item.label);
        writeField(&mut output[count].insertText, &item.insertText);
        writeField(&mut output[count].detail, &item.detail);
        count += 1;
    }
    count as u32
}

extern "C" fn goToDefinition(_userData: *mut c_void) {
    let Some((path, text)) = activeDocument() else {
        return;
    };
    let Some(api) = api() else { return };
    let mut caret = 0_u64;
    let mut length = 0_u64;
    // SAFETY: The host writes two u64 values.
    if unsafe { (api.getSelection)(api.context, &mut caret, &mut length) } != 0 {
        return;
    }
    let (line, column) = positionAtCaret(&text, caret);
    if let Ok(guard) = server().lock()
        && let Some(server) = guard.as_ref()
    {
        server.updateDocument(path.clone(), text);
        server.goToDefinition(path, line, column);
    }
}

fn counterpart(path: &Path) -> Option<PathBuf> {
    let extension = path.extension()?.to_str()?;
    let candidates: &[&str] = match extension {
        "c" => &["h"],
        "cc" | "cpp" | "cxx" => &["hpp", "h", "hh", "hxx"],
        "h" | "hpp" | "hh" | "hxx" => &["cpp", "cc", "cxx", "c"],
        _ => return None,
    };
    candidates
        .iter()
        .map(|extension| path.with_extension(extension))
        .find(|candidate| candidate.is_file())
}

extern "C" fn switchHeaderSource(_userData: *mut c_void) {
    let Some(api) = api() else { return };
    let Some(path) = copyHostString(api.copyActiveFilePath) else {
        return;
    };
    let Some(target) = counterpart(Path::new(&path)) else {
        return;
    };
    if let Some(target) = target.to_str() {
        navigate(target, 1, 0);
    }
}

fn formatText(input: &[u8]) -> Option<Vec<u8>> {
    let api = api()?;
    let path = copyHostString(api.copyActiveFilePath)?;
    let mut child = Command::new("xcrun")
        .arg("clang-format")
        .arg(format!("--assume-filename={path}"))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .ok()?;
    child.stdin.take()?.write_all(input).ok()?;
    let output = child.wait_with_output().ok()?;
    (output.status.success() && output.stdout.len() <= 16 * 1024 * 1024).then_some(output.stdout)
}

extern "C" fn formatDocument(
    _userData: *mut c_void,
    input: *const c_char,
    inputLength: u64,
    output: *mut c_char,
    outputCapacity: u64,
) -> u64 {
    if input.is_null() || inputLength > 16 * 1024 * 1024 {
        return u64::MAX;
    }
    if output.is_null() {
        // SAFETY: The host provides inputLength readable bytes for this call.
        let bytes = unsafe { std::slice::from_raw_parts(input.cast::<u8>(), inputLength as usize) };
        let formatted = formatText(bytes);
        let length = formatted
            .as_ref()
            .map_or(u64::MAX, |bytes| bytes.len() as u64);
        if let Ok(mut cache) = formatCache().lock() {
            *cache = formatted;
        }
        return length;
    }
    let Ok(mut cache) = formatCache().lock() else {
        return u64::MAX;
    };
    let Some(formatted) = cache.take() else {
        return u64::MAX;
    };
    if outputCapacity <= formatted.len() as u64 {
        return u64::MAX;
    }
    // SAFETY: The host provides outputCapacity writable bytes and the size was checked.
    unsafe {
        std::ptr::copy_nonoverlapping(formatted.as_ptr(), output.cast::<u8>(), formatted.len());
        *output.add(formatted.len()) = 0;
    }
    formatted.len() as u64
}

fn writeField<const N: usize>(target: &mut [c_char; N], source: &str) {
    for (index, byte) in source.as_bytes().iter().take(N - 1).enumerate() {
        target[index] = *byte as c_char;
    }
}

extern "C" fn panelRows(_userData: *mut c_void, rows: *mut PanelRow, capacity: u32) -> u32 {
    if rows.is_null() || capacity < 3 {
        return 0;
    }
    // SAFETY: The host allocates capacity rows and invokes this callback on the main thread.
    let rows = unsafe { std::slice::from_raw_parts_mut(rows, capacity as usize) };
    rows[0].kind = 1;
    let status = match STATUS.load(Ordering::Acquire) {
        2 => "clangd connected",
        1 => "clangd starting...",
        _ => "clangd unavailable; install Xcode Command Line Tools",
    };
    writeField(&mut rows[0].title, status);
    rows[1].kind = 2;
    writeField(&mut rows[1].title, "Go to Definition");
    writeField(&mut rows[1].commandId, "kinetic.cpp.goToDefinition");
    rows[2].kind = 2;
    writeField(&mut rows[2].title, "Switch Header / Source");
    writeField(&mut rows[2].commandId, "kinetic.cpp.switchHeaderSource");
    3
}

extern "C" fn syntaxTokens(
    _userData: *mut c_void,
    line: *const c_char,
    byteLength: u64,
    state: *mut u32,
    tokens: *mut SyntaxToken,
    capacity: u32,
) -> u32 {
    if line.is_null() || state.is_null() || tokens.is_null() || byteLength > 1024 * 1024 {
        return 0;
    }
    // SAFETY: The host passes valid line, state, and token buffers for this call.
    let bytes = unsafe { std::slice::from_raw_parts(line.cast::<u8>(), byteLength as usize) };
    let Ok(text) = std::str::from_utf8(bytes) else {
        return 0;
    };
    let output = unsafe { std::slice::from_raw_parts_mut(tokens, capacity as usize) };
    language::tokens(text, unsafe { &mut *state }, output) as u32
}

extern "C" fn start(apiPointer: *const PluginApi) -> i32 {
    // SAFETY: The host supplies the API table for the plugin lifetime.
    let Some(api) = (unsafe { apiPointer.as_ref() }) else {
        return -1;
    };
    if api.abiVersion != 1 || (api.structSize as usize) < std::mem::size_of::<PluginApi>() {
        return -1;
    }
    API.store(apiPointer.cast_mut(), Ordering::Release);
    let context = api.context;
    for extension in [c"c", c"h", c"cc", c"cpp", c"cxx", c"hpp", c"hh", c"hxx"] {
        // SAFETY: All pointers and callbacks remain valid until stop.
        if unsafe {
            (api.registerSyntaxProvider)(
                context,
                extension.as_ptr(),
                syntaxTokens,
                std::ptr::null_mut(),
            )
        } != 0
        {
            return -1;
        }
    }
    for extension in [c"c", c"h", c"cc", c"cpp", c"cxx", c"hpp", c"hh", c"hxx"] {
        if unsafe {
            (api.registerCompletionProvider)(
                context,
                extension.as_ptr(),
                completeDocument,
                std::ptr::null_mut(),
            )
        } != 0
        {
            return -1;
        }
    }
    let command = c"kinetic.cpp.goToDefinition";
    // SAFETY: Registration occurs on the host main thread.
    if unsafe {
        (api.registerCommand)(
            context,
            command.as_ptr(),
            c"Go to Definition".as_ptr(),
            goToDefinition,
            std::ptr::null_mut(),
        )
    } != 0
        || unsafe { (api.registerShortcut)(context, command.as_ptr(), c"b".as_ptr(), 1 | 4) } != 0
        || unsafe {
            (api.registerPanel)(
                context,
                c"kinetic.cpp.panel".as_ptr(),
                c"C/C++ Support".as_ptr(),
                panelRows,
                std::ptr::null_mut(),
            )
        } != 0
        || unsafe {
            (api.subscribeEvent)(
                context,
                c"document.activated".as_ptr(),
                documentEvent,
                std::ptr::null_mut(),
            )
        } != 0
        || unsafe {
            (api.subscribeEvent)(
                context,
                c"document.changed".as_ptr(),
                documentEvent,
                std::ptr::null_mut(),
            )
        } != 0
    {
        return -1;
    }
    let switchCommand = c"kinetic.cpp.switchHeaderSource";
    if unsafe {
        (api.registerCommand)(
            context,
            switchCommand.as_ptr(),
            c"Switch Header / Source".as_ptr(),
            switchHeaderSource,
            std::ptr::null_mut(),
        )
    } != 0
        || unsafe { (api.registerShortcut)(context, switchCommand.as_ptr(), c"h".as_ptr(), 1 | 4) }
            != 0
    {
        return -1;
    }
    if Command::new("xcrun")
        .args(["--find", "clang-format"])
        .output()
        .is_ok_and(|output| output.status.success())
    {
        for extension in [c"c", c"h", c"cc", c"cpp", c"cxx", c"hpp", c"hh", c"hxx"] {
            if unsafe {
                (api.registerFormatter)(
                    context,
                    extension.as_ptr(),
                    formatDocument,
                    std::ptr::null_mut(),
                )
            } != 0
            {
                return -1;
            }
        }
    }
    let workspace = copyHostString(api.copyWorkspacePath);
    match LanguageServer::start(workspace) {
        Ok(instance) => {
            STATUS.store(1, Ordering::Release);
            if let Ok(mut guard) = server().lock() {
                *guard = Some(instance);
            }
            documentEvent(std::ptr::null_mut(), std::ptr::null());
        }
        Err(_) => STATUS.store(0, Ordering::Release),
    }
    0
}

extern "C" fn stop() {
    if let Ok(mut guard) = server().lock()
        && let Some(instance) = guard.take()
    {
        instance.stop();
    }
    API.store(std::ptr::null_mut(), Ordering::Release);
    STATUS.store(0, Ordering::Release);
}

static DESCRIPTOR: PluginDescriptor = PluginDescriptor {
    abiVersion: 1,
    structSize: std::mem::size_of::<PluginDescriptor>() as u32,
    pluginId: c"kinetic.cpp-support".as_ptr(),
    displayName: c"C/C++ Support".as_ptr(),
    version: c"0.2.0".as_ptr(),
    start,
    stop,
};

#[unsafe(no_mangle)]
pub extern "C" fn kineticPluginEntry() -> *const PluginDescriptor {
    &DESCRIPTOR
}

fn publish(path: &str, diagnostics: &[Diagnostic]) {
    let Some(api) = api() else { return };
    let Ok(path) = CString::new(path) else { return };
    // SAFETY: The host copies the diagnostics before returning.
    unsafe {
        (api.publishDiagnostics)(
            api.context,
            path.as_ptr(),
            diagnostics.as_ptr(),
            diagnostics.len() as u32,
        );
    }
}

fn navigate(path: &str, line: u32, column: u32) {
    let Some(api) = api() else { return };
    let Ok(path) = CString::new(path) else { return };
    // SAFETY: The host copies the path and dispatches to its main thread.
    unsafe {
        (api.openLocation)(api.context, path.as_ptr(), line, column);
    }
}

fn diagnosticMessage(message: &str) -> [c_char; 256] {
    let mut buffer = [0; 256];
    writeField(&mut buffer, message);
    buffer
}
