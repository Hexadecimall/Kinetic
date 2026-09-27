use std::collections::HashMap;
use std::io::{self, BufRead, BufReader, Write};
use std::process::{Child, Command, Stdio};
use std::sync::{Arc, Mutex, mpsc};
use std::thread::{self, JoinHandle};

use serde_json::{Value, json};

use crate::{Diagnostic, STATUS, diagnosticMessage, navigate, publish};
use std::sync::atomic::Ordering;

struct State {
    ready: bool,
    documents: HashMap<String, u32>,
    pending: HashMap<String, String>,
    nextRequestId: u64,
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
    let language = if path.ends_with(".c") { "c" } else { "cpp" };
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
        result.push(Diagnostic {
            line,
            columnUtf16,
            lengthUtf16,
            severity,
            message: diagnosticMessage(message),
        });
    }
    Some((path, result))
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

impl LanguageServer {
    pub fn start(workspace: Option<String>) -> io::Result<Self> {
        let mut process = Command::new("clangd")
            .arg("--background-index")
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
            pending: HashMap::new(),
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
                            let _ = readerSender.send(didOpen(&path, &text));
                        }
                    }
                    STATUS.store(2, Ordering::Release);
                } else if message.get("method").and_then(Value::as_str)
                    == Some("textDocument/publishDiagnostics")
                {
                    if let Some((path, diagnostics)) = parseDiagnostics(&message) {
                        publish(&path, &diagnostics);
                    }
                } else if message.get("id").and_then(Value::as_u64).is_some()
                    && let Some((path, line, column)) = definition(&message)
                {
                    navigate(&path, line, column);
                }
            }
            STATUS.store(0, Ordering::Release);
        });
        let rootUri = workspace.as_deref().map(uri);
        let _ = sender.send(
            json!({"jsonrpc":"2.0","id":1,"method":"initialize","params":{
                "processId":std::process::id(),"rootUri":rootUri,
                "capabilities":{"general":{"positionEncodings":["utf-16"]},
                                "textDocument":{"publishDiagnostics":{}}},
                "clientInfo":{"name":"Kinetic C/C++ Support","version":"0.1.0"}
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
            Some("c" | "h" | "cc" | "cpp" | "cxx" | "hpp" | "hh" | "hxx")
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
        let message = if let Some(version) = state.documents.get_mut(&path) {
            *version = version.saturating_add(1);
            didChange(&path, &text, *version)
        } else {
            state.documents.insert(path.clone(), 1);
            didOpen(&path, &text)
        };
        let _ = self.sender.send(message);
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
    }
}
