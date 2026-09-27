//! Rust-owned document state behind an opaque, versioned C boundary.

#![allow(non_snake_case)]

use std::slice;
use std::str;

const maximumTextBytes: usize = 64 * 1024 * 1024;
const maximumHistory: usize = 256;

struct EditState {
    text: String,
    caret: u64,
    anchor: u64,
}

pub struct KineticDocument {
    text: String,
    savedText: String,
    undo: Vec<EditState>,
    redo: Vec<EditState>,
}

#[allow(unsafe_code, reason = "UTF-8 input bytes cross the C ABI")]
fn utf8Input<'a>(bytes: *const u8, length: u64) -> Option<&'a str> {
    let length = usize::try_from(length).ok()?;
    if length > maximumTextBytes || (length > 0 && bytes.is_null()) {
        return None;
    }
    if length == 0 {
        return Some("");
    }
    // SAFETY: The FFI caller guarantees that bytes points to length readable bytes for this call.
    str::from_utf8(unsafe { slice::from_raw_parts(bytes, length) }).ok()
}

fn byteIndexForUtf16(text: &str, offset: u64) -> Option<usize> {
    let mut units = 0_u64;
    for (byteIndex, character) in text.char_indices() {
        if units == offset {
            return Some(byteIndex);
        }
        units += if character.len_utf16() == 2 { 2 } else { 1 };
        if units > offset {
            return None;
        }
    }
    (units == offset).then_some(text.len())
}

#[allow(unsafe_code, reason = "opaque document ownership crosses the C ABI")]
#[unsafe(no_mangle)]
pub extern "C" fn kineticDocumentCreate(bytes: *const u8, length: u64) -> *mut KineticDocument {
    let Some(text) = utf8Input(bytes, length) else {
        return std::ptr::null_mut();
    };
    Box::into_raw(Box::new(KineticDocument {
        text: text.to_owned(),
        savedText: text.to_owned(),
        undo: Vec::new(),
        redo: Vec::new(),
    }))
}

#[allow(unsafe_code, reason = "opaque document ownership crosses the C ABI")]
#[unsafe(no_mangle)]
pub extern "C" fn kineticDocumentDestroy(document: *mut KineticDocument) {
    if !document.is_null() {
        // SAFETY: A live handle is returned by kineticDocumentCreate and destroyed only once.
        drop(unsafe { Box::from_raw(document) });
    }
}

#[allow(
    unsafe_code,
    reason = "document handles and output buffers cross the C ABI"
)]
#[unsafe(no_mangle)]
pub extern "C" fn kineticDocumentCopyUtf8(
    document: *const KineticDocument,
    buffer: *mut u8,
    capacity: u64,
) -> u64 {
    // SAFETY: The caller passes a live document handle or null.
    let Some(document) = (unsafe { document.as_ref() }) else {
        return 0;
    };
    let bytes = document.text.as_bytes();
    if !buffer.is_null() && capacity > bytes.len() as u64 {
        // SAFETY: Capacity is supplied by the caller and checked above.
        unsafe {
            std::ptr::copy_nonoverlapping(bytes.as_ptr(), buffer, bytes.len());
            *buffer.add(bytes.len()) = 0;
        }
    }
    bytes.len() as u64
}

#[allow(unsafe_code, reason = "document handles cross the C ABI")]
#[unsafe(no_mangle)]
pub extern "C" fn kineticDocumentCheckpoint(
    document: *mut KineticDocument,
    caret: u64,
    anchor: u64,
) -> i32 {
    // SAFETY: The caller passes a live document handle or null.
    let Some(document) = (unsafe { document.as_mut() }) else {
        return -1;
    };
    let length = document.text.encode_utf16().count() as u64;
    if caret > length || anchor > length {
        return -1;
    }
    if document.undo.len() == maximumHistory {
        document.undo.remove(0);
    }
    document.undo.push(EditState {
        text: document.text.clone(),
        caret,
        anchor,
    });
    document.redo.clear();
    0
}

#[allow(unsafe_code, reason = "document handles cross the C ABI")]
#[unsafe(no_mangle)]
pub extern "C" fn kineticDocumentReplaceUtf8(
    document: *mut KineticDocument,
    startUtf16: u64,
    lengthUtf16: u64,
    bytes: *const u8,
    byteLength: u64,
) -> i32 {
    // SAFETY: The caller passes a live document handle or null.
    let Some(document) = (unsafe { document.as_mut() }) else {
        return -1;
    };
    let Some(replacement) = utf8Input(bytes, byteLength) else {
        return -1;
    };
    let Some(endUtf16) = startUtf16.checked_add(lengthUtf16) else {
        return -1;
    };
    let Some(start) = byteIndexForUtf16(&document.text, startUtf16) else {
        return -1;
    };
    let Some(end) = byteIndexForUtf16(&document.text, endUtf16) else {
        return -1;
    };
    let Some(newLength) = document
        .text
        .len()
        .checked_sub(end - start)
        .and_then(|length| length.checked_add(replacement.len()))
    else {
        return -1;
    };
    if newLength > maximumTextBytes {
        return -1;
    }
    document.text.replace_range(start..end, replacement);
    0
}

#[allow(
    unsafe_code,
    reason = "document handles and selection outputs cross the C ABI"
)]
#[unsafe(no_mangle)]
pub extern "C" fn kineticDocumentHistoryStep(
    document: *mut KineticDocument,
    redo: bool,
    currentCaret: u64,
    currentAnchor: u64,
    nextCaret: *mut u64,
    nextAnchor: *mut u64,
) -> i32 {
    // SAFETY: The caller passes a live document handle or null.
    let Some(document) = (unsafe { document.as_mut() }) else {
        return -1;
    };
    if nextCaret.is_null() || nextAnchor.is_null() {
        return -1;
    }
    let (source, destination) = if redo {
        (&mut document.redo, &mut document.undo)
    } else {
        (&mut document.undo, &mut document.redo)
    };
    let Some(state) = source.pop() else {
        return -1;
    };
    destination.push(EditState {
        text: std::mem::replace(&mut document.text, state.text),
        caret: currentCaret,
        anchor: currentAnchor,
    });
    // SAFETY: Both non-null output pointers are writable for one u64 as required by this API.
    unsafe {
        *nextCaret = state.caret;
        *nextAnchor = state.anchor;
    }
    0
}

#[allow(unsafe_code, reason = "document handles cross the C ABI")]
#[unsafe(no_mangle)]
pub extern "C" fn kineticDocumentCanUndo(document: *const KineticDocument) -> bool {
    // SAFETY: The caller passes a live document handle or null.
    unsafe { document.as_ref() }.is_some_and(|document| !document.undo.is_empty())
}

#[allow(unsafe_code, reason = "document handles cross the C ABI")]
#[unsafe(no_mangle)]
pub extern "C" fn kineticDocumentCanRedo(document: *const KineticDocument) -> bool {
    // SAFETY: The caller passes a live document handle or null.
    unsafe { document.as_ref() }.is_some_and(|document| !document.redo.is_empty())
}

#[allow(unsafe_code, reason = "document handles cross the C ABI")]
#[unsafe(no_mangle)]
pub extern "C" fn kineticDocumentIsDirty(document: *const KineticDocument) -> bool {
    // SAFETY: The caller passes a live document handle or null.
    unsafe { document.as_ref() }.is_some_and(|document| document.text != document.savedText)
}

#[allow(unsafe_code, reason = "document handles cross the C ABI")]
#[unsafe(no_mangle)]
pub extern "C" fn kineticDocumentMarkSaved(document: *mut KineticDocument) {
    // SAFETY: The caller passes a live document handle or null.
    if let Some(document) = unsafe { document.as_mut() } {
        document.savedText.clone_from(&document.text);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn editsUseUtf16OffsetsAndTrackHistory() {
        let original = "A🦀B";
        let document = kineticDocumentCreate(original.as_ptr(), original.len() as u64);
        assert!(!document.is_null());
        assert_eq!(kineticDocumentCheckpoint(document, 3, 3), 0);
        assert_eq!(
            kineticDocumentReplaceUtf8(document, 1, 2, "Z".as_ptr(), 1),
            0
        );
        assert!(kineticDocumentIsDirty(document));
        assert_eq!(
            kineticDocumentCopyUtf8(document, std::ptr::null_mut(), 0),
            3
        );
        let mut caret = 0;
        let mut anchor = 0;
        assert_eq!(
            kineticDocumentHistoryStep(document, false, 2, 2, &raw mut caret, &raw mut anchor),
            0
        );
        assert_eq!((caret, anchor), (3, 3));
        assert!(!kineticDocumentIsDirty(document));
        assert!(kineticDocumentCanRedo(document));
        assert_eq!(
            kineticDocumentHistoryStep(document, true, 3, 3, &raw mut caret, &raw mut anchor),
            0
        );
        assert_eq!((caret, anchor), (2, 2));
        kineticDocumentMarkSaved(document);
        assert!(!kineticDocumentIsDirty(document));
        kineticDocumentDestroy(document);
    }

    #[test]
    fn rejectsSplitSurrogatesAndInvalidUtf8() {
        let original = "🦀";
        let document = kineticDocumentCreate(original.as_ptr(), original.len() as u64);
        assert_eq!(
            kineticDocumentReplaceUtf8(document, 1, 0, "x".as_ptr(), 1),
            -1
        );
        assert_eq!(
            kineticDocumentReplaceUtf8(document, 0, 2, [0xff].as_ptr(), 1),
            -1
        );
        kineticDocumentDestroy(document);
    }
}
