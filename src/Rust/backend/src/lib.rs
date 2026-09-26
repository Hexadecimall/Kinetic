//! Kinetic's editor-core boundary.
//!
//! The implementation is intentionally small during the foundation phase. The exported functions
//! establish the versioned C ABI without exposing Rust layouts or ownership across the boundary.

#![allow(non_snake_case, non_upper_case_globals)]

use std::ffi::c_char;

const abiVersion: u32 = 1;
const versionBytes: &[u8] = concat!(env!("CARGO_PKG_VERSION"), "\0").as_bytes();

/// Returns the version of the C ABI implemented by this backend.
#[allow(unsafe_code, reason = "the stable C ABI requires an unmangled export")]
#[unsafe(no_mangle)]
pub extern "C" fn kineticBackendAbiVersion() -> u32 {
    abiVersion
}

/// Returns Kinetic's semantic version as a process-lifetime UTF-8 C string.
#[allow(unsafe_code, reason = "the stable C ABI requires an unmangled export")]
#[unsafe(no_mangle)]
pub extern "C" fn kineticBackendVersion() -> *const c_char {
    versionBytes.as_ptr().cast()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn abiStartsAtOne() {
        assert_eq!(kineticBackendAbiVersion(), 1);
    }

    #[test]
    fn versionIsStableUtf8() {
        assert_eq!(
            &versionBytes[..versionBytes.len() - 1],
            env!("CARGO_PKG_VERSION").as_bytes()
        );
    }
}
