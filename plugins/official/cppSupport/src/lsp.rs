use std::collections::HashMap;
use std::io::{self, BufRead, BufReader, Write};
use std::path::{Path, PathBuf};
use std::process::{Child, Stdio};
use std::sync::{Arc, Mutex, mpsc};
use std::thread::{self, JoinHandle};
use std::time::Duration;

use serde_json::{Value, json};

use crate::{Diagnostic, STATUS, diagnosticMessage, navigate, publish};
use std::sync::atomic::Ordering;

struct State {
    ready: bool,
    documents: HashMap<String, u32>,
    documentTexts: HashMap<String, String>,
    diagnostics: HashMap<String, Vec<Value>>,
    pending: HashMap<String, String>,
    pendingCompletions: HashMap<u64, CompletionQuery>,
    pendingFixes: HashMap<u64, mpsc::Sender<Value>>,
    lastCompletionQuery: Option<CompletionQuery>,
    completionItems: Vec<CompletionItem>,
    nextRequestId: u64,
}

#[derive(Clone, PartialEq, Eq)]
struct CompletionQuery {
    path: String,
    version: u32,
    line: u32,
    column: u32,
    prefix: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CompletionItem {
    pub label: String,
    pub insertText: String,
    pub detail: String,
}

pub struct FixEdit {
    pub startUtf16: u64,
    pub lengthUtf16: u64,
    pub text: String,
}

fn utf16Offset(text: &str, line: u64, column: u64) -> Option<u64> {
    let mut offset = 0_u64;
    for (index, content) in text.split('\n').enumerate() {
        if index as u64 == line {
            let mut width = 0_u64;
            for character in content.chars() {
                if width == column {
                    return Some(offset + width);
                }
                width += character.len_utf16() as u64;
                if width > column {
                    return None;
                }
            }
            return (width == column).then_some(offset + width);
        }
        offset += content.encode_utf16().count() as u64 + 1;
    }
    None
}

fn parseEdit(text: &str, value: &Value) -> Option<FixEdit> {
    let start = value.pointer("/range/start")?;
    let end = value.pointer("/range/end")?;
    let start = utf16Offset(
        text,
        start.get("line")?.as_u64()?,
        start.get("character")?.as_u64()?,
    )?;
    let end = utf16Offset(
        text,
        end.get("line")?.as_u64()?,
        end.get("character")?.as_u64()?,
    )?;
    (end >= start).then_some(FixEdit {
        startUtf16: start,
        lengthUtf16: end - start,
        text: value.get("newText")?.as_str()?.to_owned(),
    })
}

pub fn quickFixEdits(response: &Value, path: &str, text: &str) -> Option<Vec<FixEdit>> {
    let actions = response.get("result")?.as_array()?;
    let target = uri(path);
    for action in actions {
        if action
            .get("kind")
            .and_then(Value::as_str)
            .is_some_and(|kind| !kind.starts_with("quickfix"))
        {
            continue;
        }
        let edit = action.get("edit").or_else(|| {
            (action.get("command").and_then(Value::as_str) == Some("clangd.applyFix"))
                .then(|| action.pointer("/arguments/0"))
                .flatten()
        });
        let Some(edit) = edit else { continue };
        let values = if let Some(changes) = edit.get("changes").and_then(Value::as_object) {
            if changes.len() != 1 {
                continue;
            }
            changes.get(&target).and_then(Value::as_array)
        } else if let Some(changes) = edit.get("documentChanges").and_then(Value::as_array) {
            if changes.len() != 1
                || changes[0]
                    .pointer("/textDocument/uri")
                    .and_then(Value::as_str)
                    != Some(target.as_str())
            {
                continue;
            }
            changes[0].get("edits").and_then(Value::as_array)
        } else {
            None
        };
        let Some(values) = values else { continue };
        if values.is_empty() || values.len() > 32 {
            continue;
        }
        let mut result = Vec::with_capacity(values.len());
        for value in values {
            let Some(parsed) = parseEdit(text, value) else {
                result.clear();
                break;
            };
            result.push(parsed);
        }
        if result.is_empty() {
            continue;
        }
        result.sort_by_key(|edit| std::cmp::Reverse(edit.startUtf16));
        if result
            .windows(2)
            .any(|pair| pair[1].startUtf16 + pair[1].lengthUtf16 > pair[0].startUtf16)
        {
            continue;
        }
        return Some(result);
    }
    None
}

pub struct LanguageServer {
    child: Arc<Mutex<Child>>,
    sender: mpsc::Sender<Value>,
    state: Arc<Mutex<State>>,
    reader: JoinHandle<()>,
    writer: JoinHandle<()>,
}

fn uri(path: &str) -> String {
    let mut result = String::from("file://");
    for byte in path.bytes() {
        if byte.is_ascii_alphanumeric() || b"/-._~".contains(&byte) {
            result.push(byte as char);
        } else {
            result.push_str(&format!("%{byte:02X}"));
        }
    }
    result
}

fn path(uri: &str) -> Option<String> {
    let bytes = uri.strip_prefix("file://")?.as_bytes();
    let mut decoded = Vec::with_capacity(bytes.len());
    let mut index = 0;
    while index < bytes.len() {
        if bytes[index] == b'%' {
            let value = u8::from_str_radix(
                std::str::from_utf8(bytes.get(index + 1..index + 3)?).ok()?,
                16,
            )
            .ok()?;
            decoded.push(value);
            index += 3;
        } else {
            decoded.push(bytes[index]);
            index += 1;
        }
    }
    let path = String::from_utf8(decoded).ok()?;
    path.starts_with('/').then_some(path)
}

fn frame(value: &Value) -> io::Result<Vec<u8>> {
    let body = serde_json::to_vec(value)?;
    let mut framed = format!("Content-Length: {}\r\n\r\n", body.len()).into_bytes();
    framed.extend(body);
    Ok(framed)
}

fn readFrame<R: BufRead>(input: &mut R) -> io::Result<Option<Value>> {
    let mut contentLength = None;
    loop {
        let mut header = String::new();
        if input.read_line(&mut header)? == 0 {
            return Ok(None);
        }
        if header == "\r\n" || header == "\n" {
            break;
        }
        if let Some((name, value)) = header.split_once(':')
            && name.eq_ignore_ascii_case("Content-Length")
        {
            contentLength = value.trim().parse::<usize>().ok();
        }
    }
    let length = contentLength
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidData, "missing Content-Length"))?;
    if length > 8 * 1024 * 1024 {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "oversized LSP message",
        ));
    }
    let mut body = vec![0; length];
    input.read_exact(&mut body)?;
    serde_json::from_slice(&body)
        .map(Some)
        .map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error))
}

fn didOpen(path: &str, text: &str) -> Value {
    let language = match path.rsplit('.').next() {
        Some("c") => "c",
        Some("m") => "objective-c",
        Some("mm") => "objective-cpp",
        _ => "cpp",
    };
    json!({"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{
        "uri":uri(path),"languageId":language,"version":1,"text":text
    }}})
}

fn didChange(path: &str, text: &str, version: u32) -> Value {
    json!({"jsonrpc":"2.0","method":"textDocument/didChange","params":{
        "textDocument":{"uri":uri(path),"version":version},"contentChanges":[{"text":text}]
    }})
}

fn parseDiagnostics(message: &Value) -> Option<(String, Vec<Diagnostic>)> {
    let params = message.get("params")?;
    let path = path(params.get("uri")?.as_str()?)?;
    let values = params.get("diagnostics")?.as_array()?;
    let mut result = Vec::new();
    for item in values.iter().take(2048) {
        let start = item.pointer("/range/start")?;
        let end = item.pointer("/range/end")?;
        let line = u32::try_from(start.get("line")?.as_u64()?)
            .ok()?
            .saturating_add(1);
        let columnUtf16 = u32::try_from(start.get("character")?.as_u64()?).ok()?;
        let endLine = u32::try_from(end.get("line")?.as_u64()?).ok()?;
        let endColumn = u32::try_from(end.get("character")?.as_u64()?).ok()?;
        let lengthUtf16 = if endLine + 1 == line {
            endColumn.saturating_sub(columnUtf16)
        } else {
            1
        };
        let severity = u32::try_from(item.get("severity").and_then(Value::as_u64).unwrap_or(3))
            .unwrap_or(3)
            .clamp(1, 3);
        let message = item.get("message").and_then(Value::as_str).unwrap_or("");
        let fixAvailable = message.ends_with("(fix available)");
        result.push(Diagnostic {
            line,
            columnUtf16,
            lengthUtf16,
            severity,
            flags: u32::from(fixAvailable),
            message: diagnosticMessage(message.trim_end_matches(" (fix available)")),
        });
    }
    Some((path, result))
}

fn compilationDatabase(workspace: &str) -> Option<PathBuf> {
    let root = Path::new(workspace);
    let candidates = [
        root.to_path_buf(),
        root.join("build/debug"),
        root.join("build/Debug"),
        root.join("build/release"),
        root.join("build/Release"),
        root.join("build"),
        root.join("out/build"),
        root.join("cmake-build-debug"),
        root.join("cmake-build-release"),
    ];
    candidates
        .into_iter()
        .find(|directory| directory.join("compile_commands.json").is_file())
}

fn definition(message: &Value) -> Option<(String, u32, u32)> {
    let result = message.get("result")?;
    let location = if let Some(items) = result.as_array() {
        items.first()?
    } else {
        result
    };
    let targetUri = location
        .get("targetUri")
        .or_else(|| location.get("uri"))?
        .as_str()?;
    let start = location
        .pointer("/targetSelectionRange/start")
        .or_else(|| location.pointer("/targetRange/start"))
        .or_else(|| location.pointer("/range/start"))?;
    Some((
        path(targetUri)?,
        u32::try_from(start.get("line")?.as_u64()?)
            .ok()?
            .saturating_add(1),
        u32::try_from(start.get("character")?.as_u64()?).ok()?,
    ))
}

fn completionItems(message: &Value) -> Vec<CompletionItem> {
    let result = message.get("result");
    let values = result.and_then(Value::as_array).or_else(|| {
        result
            .and_then(|value| value.get("items"))
            .and_then(Value::as_array)
    });
    let Some(values) = values else {
        return Vec::new();
    };
    values
        .iter()
        .filter_map(|item| {
            let label = item.get("label")?.as_str()?.trim();
            let insertion = item
                .pointer("/textEdit/newText")
                .or_else(|| item.get("insertText"))
                .and_then(Value::as_str)
                .unwrap_or(label);
            let insertText = if item.get("insertTextFormat").and_then(Value::as_u64) == Some(2)
                || insertion.contains('$')
            {
                item.get("filterText")
                    .and_then(Value::as_str)
                    .unwrap_or_else(|| label.split('(').next().unwrap_or(label))
            } else {
                insertion
            };
            if label.is_empty() || insertText.is_empty() {
                return None;
            }
            let detail = item.get("detail").and_then(Value::as_str).unwrap_or("");
            Some(CompletionItem {
                label: label.chars().take(95).collect(),
                insertText: insertText.chars().take(95).collect(),
                detail: detail.chars().take(95).collect(),
            })
        })
        .take(32)
        .collect()
}

impl LanguageServer {
    pub fn start(workspace: Option<String>) -> io::Result<Self> {
        let mut command = crate::tools::command("clangd");
        command.arg("--background-index");
        if let Some(directory) = workspace.as_deref().and_then(compilationDatabase) {
            command.arg(format!("--compile-commands-dir={}", directory.display()));
        }
        let mut process = command
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()?;
        let stdin = process
            .stdin
            .take()
            .ok_or_else(|| io::Error::other("clangd stdin unavailable"))?;
        let stdout = process
            .stdout
            .take()
            .ok_or_else(|| io::Error::other("clangd stdout unavailable"))?;
        let child = Arc::new(Mutex::new(process));
        let (sender, receiver) = mpsc::channel::<Value>();
        let writer = thread::spawn(move || {
            let mut stdin = stdin;
            while let Ok(message) = receiver.recv() {
                let Ok(bytes) = frame(&message) else { break };
                if stdin
                    .write_all(&bytes)
                    .and_then(|()| stdin.flush())
                    .is_err()
                {
                    break;
                }
            }
        });
        let state = Arc::new(Mutex::new(State {
            ready: false,
            documents: HashMap::new(),
            documentTexts: HashMap::new(),
            diagnostics: HashMap::new(),
            pending: HashMap::new(),
            pendingCompletions: HashMap::new(),
            pendingFixes: HashMap::new(),
            lastCompletionQuery: None,
            completionItems: Vec::new(),
            nextRequestId: 2,
        }));
        let readerState = Arc::clone(&state);
        let readerSender = sender.clone();
        let reader = thread::spawn(move || {
            let mut input = BufReader::new(stdout);
            while let Ok(Some(message)) = readFrame(&mut input) {
                if message.get("id").and_then(Value::as_u64) == Some(1) {
                    if message.get("error").is_some() {
                        break;
                    }
                    let _ = readerSender
                        .send(json!({"jsonrpc":"2.0","method":"initialized","params":{}}));
                    if let Ok(mut state) = readerState.lock() {
                        state.ready = true;
                        let pending = std::mem::take(&mut state.pending);
                        for (path, text) in pending {
                            state.documents.insert(path.clone(), 1);
                            state.documentTexts.insert(path.clone(), text.clone());
                            let _ = readerSender.send(didOpen(&path, &text));
                        }
                    }
                    STATUS.store(2, Ordering::Release);
                } else if message.get("method").and_then(Value::as_str)
                    == Some("textDocument/publishDiagnostics")
                {
                    if let Some((path, diagnostics)) = parseDiagnostics(&message) {
                        if let Ok(mut state) = readerState.lock() {
                            let raw = message
                                .pointer("/params/diagnostics")
                                .and_then(Value::as_array)
                                .cloned()
                                .unwrap_or_default();
                            state.diagnostics.insert(path.clone(), raw);
                        }
                        publish(&path, &diagnostics);
                    }
                } else if let Some(id) = message.get("id").and_then(Value::as_u64) {
                    if let Some(reply) = readerState
                        .lock()
                        .ok()
                        .and_then(|mut state| state.pendingFixes.remove(&id))
                    {
                        let _ = reply.send(message);
                        continue;
                    }
                    let completion = readerState
                        .lock()
                        .ok()
                        .and_then(|mut state| state.pendingCompletions.remove(&id));
                    if let Some(query) = completion {
                        if let Ok(mut state) = readerState.lock()
                            && state.lastCompletionQuery.as_ref() == Some(&query)
                        {
                            state.completionItems = completionItems(&message);
                        }
                    } else if let Some((path, line, column)) = definition(&message) {
                        navigate(&path, line, column);
                    }
                }
            }
            STATUS.store(0, Ordering::Release);
        });
        let rootUri = workspace.as_deref().map(uri);
        let _ = sender.send(
            json!({"jsonrpc":"2.0","id":1,"method":"initialize","params":{
                "processId":std::process::id(),"rootUri":rootUri,
                "capabilities":{"general":{"positionEncodings":["utf-16"]},
                                "textDocument":{"publishDiagnostics":{},
                                                "completion":{"completionItem":{"snippetSupport":false}}}},
                "clientInfo":{"name":"Kinetic C/C++ Support","version":env!("CARGO_PKG_VERSION")}
            }}),
        );
        Ok(Self {
            child,
            sender,
            state,
            reader,
            writer,
        })
    }

    pub fn updateDocument(&self, path: String, text: String) {
        if !matches!(
            path.rsplit('.').next(),
            Some("c" | "h" | "cc" | "cpp" | "cxx" | "hpp" | "hh" | "hxx" | "m" | "mm")
        ) {
            return;
        }
        let Ok(mut state) = self.state.lock() else {
            return;
        };
        if !state.ready {
            state.pending.insert(path, text);
            return;
        }
        if state.documentTexts.get(&path) == Some(&text) {
            return;
        }
        state.documentTexts.insert(path.clone(), text.clone());
        state.lastCompletionQuery = None;
        state.completionItems.clear();
        let message = if let Some(version) = state.documents.get_mut(&path) {
            *version = version.saturating_add(1);
            didChange(&path, &text, *version)
        } else {
            state.documents.insert(path.clone(), 1);
            didOpen(&path, &text)
        };
        let _ = self.sender.send(message);
    }

    pub fn requestCompletions(
        &self,
        path: String,
        text: String,
        line: u32,
        column: u32,
        prefix: String,
    ) -> Vec<CompletionItem> {
        self.updateDocument(path.clone(), text);
        let Ok(mut state) = self.state.lock() else {
            return Vec::new();
        };
        let Some(&version) = state.documents.get(&path) else {
            return Vec::new();
        };
        if !state.ready {
            return Vec::new();
        }
        let query = CompletionQuery {
            path: path.clone(),
            version,
            line,
            column,
            prefix,
        };
        if state.lastCompletionQuery.as_ref() == Some(&query) {
            return state.completionItems.clone();
        }
        state.lastCompletionQuery = Some(query.clone());
        state.completionItems.clear();
        state.pendingCompletions.clear();
        let id = state.nextRequestId;
        state.nextRequestId += 1;
        state.pendingCompletions.insert(id, query);
        let _ = self.sender.send(json!({"jsonrpc":"2.0","id":id,
        "method":"textDocument/completion","params":{
            "textDocument":{"uri":uri(&path)},
            "position":{"line":line,"character":column},
            "context":{"triggerKind":1}
        }}));
        Vec::new()
    }

    pub fn goToDefinition(&self, path: String, line: u32, column: u32) {
        let Ok(mut state) = self.state.lock() else {
            return;
        };
        if !state.ready {
            return;
        }
        let id = state.nextRequestId;
        state.nextRequestId += 1;
        let _ = self.sender.send(
            json!({"jsonrpc":"2.0","id":id,"method":"textDocument/definition","params":{
                "textDocument":{"uri":uri(&path)},"position":{"line":line,"character":column}
            }}),
        );
    }

    pub fn quickFix(&self, path: &str, line: u32, column: u32, length: u32) -> Option<Value> {
        let (reply, receiver) = mpsc::channel();
        let Ok(mut state) = self.state.lock() else {
            return None;
        };
        if !state.ready || !state.documents.contains_key(path) {
            return None;
        }
        let id = state.nextRequestId;
        state.nextRequestId += 1;
        state.pendingFixes.insert(id, reply);
        let diagnostics: Vec<Value> = state
            .diagnostics
            .get(path)
            .into_iter()
            .flatten()
            .filter(|item| {
                item.pointer("/range/start/line").and_then(Value::as_u64) == Some(line as u64)
                    && item
                        .pointer("/range/start/character")
                        .and_then(Value::as_u64)
                        == Some(column as u64)
            })
            .cloned()
            .collect();
        drop(state);
        let request = json!({"jsonrpc":"2.0","id":id,"method":"textDocument/codeAction","params":{
            "textDocument":{"uri":uri(path)},
            "range":{"start":{"line":line,"character":column},
                     "end":{"line":line,"character":column.saturating_add(length.max(1))}},
            "context":{"diagnostics":diagnostics,"only":["quickfix"]}
        }});
        if self.sender.send(request).is_err() {
            return None;
        }
        receiver.recv_timeout(Duration::from_millis(800)).ok()
    }

    pub fn stop(self) {
        if let Ok(mut child) = self.child.lock() {
            let _ = child.kill();
        }
        drop(self.sender);
        let _ = self.reader.join();
        let _ = self.writer.join();
        if let Ok(mut child) = self.child.lock() {
            let _ = child.wait();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn framedJsonRoundTrips() {
        let value = json!({"jsonrpc":"2.0","id":1,"result":{"ok":true}});
        let bytes = frame(&value).unwrap();
        assert_eq!(
            readFrame(&mut BufReader::new(bytes.as_slice())).unwrap(),
            Some(value)
        );
    }

    #[test]
    fn uriAndLspMessages() {
        assert_eq!(
            path(&uri("/tmp/C++ demo/é.cpp")),
            Some("/tmp/C++ demo/é.cpp".into())
        );
        let message = json!({"params":{"uri":"file:///tmp/demo.cpp","diagnostics":[{
            "range":{"start":{"line":2,"character":4},"end":{"line":2,"character":8}},
            "severity":1,"message":"unknown symbol"
        }]}});
        let (file, diagnostics) = parseDiagnostics(&message).unwrap();
        assert_eq!(file, "/tmp/demo.cpp");
        assert_eq!(diagnostics[0].line, 3);
        assert_eq!(diagnostics[0].lengthUtf16, 4);
        let destination = json!({"result":{"uri":"file:///tmp/header.hpp","range":{"start":{"line":4,"character":2}}}});
        assert_eq!(
            definition(&destination),
            Some(("/tmp/header.hpp".into(), 5, 2))
        );
        let message = json!({"params":{"uri":"file:///tmp/demo.cpp","diagnostics":[{
            "range":{"start":{"line":0,"character":0},"end":{"line":0,"character":5}},
            "severity":2,"message":"Unused include (fix available)"
        }]}});
        let (_, diagnostics) = parseDiagnostics(&message).unwrap();
        assert_eq!(diagnostics[0].flags, 1);
        assert_eq!(diagnostics[0].message[0] as u8, b'U');
    }

    #[test]
    fn discoversCMakeDatabaseAndParsesSameFileFix() {
        let root = std::env::temp_dir().join(format!("kinetic-clangd-{}", std::process::id()));
        let directory = root.join("build/debug");
        std::fs::create_dir_all(&directory).unwrap();
        std::fs::write(directory.join("compile_commands.json"), "[]").unwrap();
        assert_eq!(compilationDatabase(root.to_str().unwrap()), Some(directory));
        let _ = std::fs::remove_dir_all(root);
        let response = json!({"result":[{"kind":"quickfix","edit":{"changes":{
            "file:///tmp/demo.cpp":[{"range":{"start":{"line":0,"character":0},
            "end":{"line":0,"character":4}},"newText":""}]
        }}}]});
        let edits = quickFixEdits(&response, "/tmp/demo.cpp", "test\n").unwrap();
        assert_eq!(edits.len(), 1);
        assert_eq!(edits[0].lengthUtf16, 4);
    }
}
