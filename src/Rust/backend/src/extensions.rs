//! Stable contribution metadata and collision rules for native plugins.

#![allow(non_snake_case)]

use std::ffi::{CStr, c_char};

const maximumFieldBytes: usize = 256;

struct Contribution {
    owner: String,
    kind: u32,
    identifier: String,
    title: String,
    target: String,
}

pub struct KineticExtensionRegistry {
    contributions: Vec<Contribution>,
}

#[allow(unsafe_code, reason = "opaque registry ownership crosses the C ABI")]
#[unsafe(no_mangle)]
pub extern "C" fn kineticExtensionRegistryCreate() -> *mut KineticExtensionRegistry {
    Box::into_raw(Box::new(KineticExtensionRegistry {
        contributions: Vec::new(),
    }))
}

#[allow(unsafe_code, reason = "opaque registry ownership crosses the C ABI")]
#[unsafe(no_mangle)]
pub extern "C" fn kineticExtensionRegistryDestroy(registry: *mut KineticExtensionRegistry) {
    if !registry.is_null() {
        // SAFETY: A live handle is returned by kineticExtensionRegistryCreate and destroyed once.
        drop(unsafe { Box::from_raw(registry) });
    }
}

#[allow(unsafe_code, reason = "NUL-terminated fields cross the C ABI")]
fn inputField(pointer: *const c_char, maximum: usize) -> Option<String> {
    if pointer.is_null() {
        return None;
    }
    // SAFETY: Native plugin callers supply a valid NUL-terminated string for the duration of the call.
    let value = unsafe { CStr::from_ptr(pointer) }.to_str().ok()?;
    if value.is_empty() || value.len() > maximum || value.chars().any(char::is_control) {
        return None;
    }
    Some(value.to_owned())
}

#[allow(unsafe_code, reason = "contribution metadata crosses the C ABI")]
#[unsafe(no_mangle)]
pub extern "C" fn kineticExtensionRegister(
    registry: *mut KineticExtensionRegistry,
    owner: *const c_char,
    kind: u32,
    identifier: *const c_char,
    title: *const c_char,
    target: *const c_char,
) -> i32 {
    // SAFETY: The caller passes a live registry handle or null.
    let Some(registry) = (unsafe { registry.as_mut() }) else {
        return -1;
    };
    let (Some(owner), Some(identifier), Some(title), Some(target)) = (
        inputField(owner, 128),
        inputField(identifier, 128),
        inputField(title, 128),
        inputField(target, maximumFieldBytes),
    ) else {
        return -1;
    };
    if !(1..=8).contains(&kind)
        || registry
            .contributions
            .iter()
            .any(|item| item.kind == kind && item.identifier == identifier)
        || (kind == 2
            && registry
                .contributions
                .iter()
                .any(|item| item.kind == kind && item.target == target))
    {
        return -1;
    }
    registry.contributions.push(Contribution {
        owner,
        kind,
        identifier,
        title,
        target,
    });
    0
}

#[allow(
    unsafe_code,
    reason = "registry handles and owner names cross the C ABI"
)]
#[unsafe(no_mangle)]
pub extern "C" fn kineticExtensionRemoveOwner(
    registry: *mut KineticExtensionRegistry,
    owner: *const c_char,
) {
    // SAFETY: The caller passes a live registry handle or null.
    let Some(registry) = (unsafe { registry.as_mut() }) else {
        return;
    };
    if let Some(owner) = inputField(owner, 128) {
        registry.contributions.retain(|item| item.owner != owner);
    }
}

#[allow(unsafe_code, reason = "registry handles cross the C ABI")]
#[unsafe(no_mangle)]
pub extern "C" fn kineticExtensionCount(
    registry: *const KineticExtensionRegistry,
    kind: u32,
) -> u64 {
    // SAFETY: The caller passes a live registry handle or null.
    unsafe { registry.as_ref() }.map_or(0, |registry| {
        registry
            .contributions
            .iter()
            .filter(|item| item.kind == kind)
            .count() as u64
    })
}

#[allow(
    unsafe_code,
    reason = "registry handles and output buffers cross the C ABI"
)]
#[unsafe(no_mangle)]
pub extern "C" fn kineticExtensionCopyField(
    registry: *const KineticExtensionRegistry,
    kind: u32,
    index: u64,
    field: u32,
    buffer: *mut c_char,
    capacity: u64,
) -> u64 {
    // SAFETY: The caller passes a live registry handle or null.
    let Some(registry) = (unsafe { registry.as_ref() }) else {
        return u64::MAX;
    };
    let Ok(index) = usize::try_from(index) else {
        return u64::MAX;
    };
    let Some(item) = registry
        .contributions
        .iter()
        .filter(|item| item.kind == kind)
        .nth(index)
    else {
        return u64::MAX;
    };
    let value = match field {
        1 => &item.identifier,
        2 => &item.title,
        3 => &item.target,
        4 => &item.owner,
        _ => return u64::MAX,
    };
    let bytes = value.as_bytes();
    if !buffer.is_null() && capacity > bytes.len() as u64 {
        // SAFETY: The caller promises buffer is writable for capacity bytes, checked above.
        unsafe {
            std::ptr::copy_nonoverlapping(bytes.as_ptr(), buffer.cast(), bytes.len());
            *buffer.add(bytes.len()) = 0;
        }
    }
    bytes.len() as u64
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;

    #[test]
    fn registriesRejectCollisionsAndRollbackOwner() {
        let registry = kineticExtensionRegistryCreate();
        let owner = CString::new("example.plugin").unwrap();
        let id = CString::new("example.command").unwrap();
        let title = CString::new("Example").unwrap();
        let target = CString::new("command").unwrap();
        assert_eq!(
            kineticExtensionRegister(
                registry,
                owner.as_ptr(),
                1,
                id.as_ptr(),
                title.as_ptr(),
                target.as_ptr(),
            ),
            0
        );
        assert_eq!(
            kineticExtensionRegister(
                registry,
                owner.as_ptr(),
                1,
                id.as_ptr(),
                title.as_ptr(),
                target.as_ptr(),
            ),
            -1
        );
        assert_eq!(kineticExtensionCount(registry, 1), 1);
        kineticExtensionRemoveOwner(registry, owner.as_ptr());
        assert_eq!(kineticExtensionCount(registry, 1), 0);
        kineticExtensionRegistryDestroy(registry);
    }

    #[test]
    #[allow(
        unsafe_code,
        reason = "the ABI test reads its own NUL-terminated output buffer"
    )]
    fn shortcutChordsAreUniqueAndFieldsAreReadable() {
        let registry = kineticExtensionRegistryCreate();
        let firstOwner = CString::new("first.plugin").unwrap();
        let secondOwner = CString::new("second.plugin").unwrap();
        let firstId = CString::new("first.command").unwrap();
        let secondId = CString::new("second.command").unwrap();
        let title = CString::new("Run").unwrap();
        let chord = CString::new("3:p").unwrap();
        assert_eq!(
            kineticExtensionRegister(
                registry,
                firstOwner.as_ptr(),
                2,
                firstId.as_ptr(),
                title.as_ptr(),
                chord.as_ptr(),
            ),
            0
        );
        assert_eq!(
            kineticExtensionRegister(
                registry,
                secondOwner.as_ptr(),
                2,
                secondId.as_ptr(),
                title.as_ptr(),
                chord.as_ptr(),
            ),
            -1
        );
        let mut buffer = [0_i8; 32];
        assert_eq!(
            kineticExtensionCopyField(registry, 2, 0, 1, buffer.as_mut_ptr(), 32),
            13
        );
        assert_eq!(
            unsafe { CStr::from_ptr(buffer.as_ptr()) }.to_str().unwrap(),
            "first.command"
        );
        kineticExtensionRegistryDestroy(registry);
    }
}
