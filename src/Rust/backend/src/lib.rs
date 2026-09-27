//! Kinetic's editor-core boundary. Rust owns document text, save state, and edit history.

#![allow(non_snake_case, non_upper_case_globals)]

use std::ffi::c_char;

mod document;
mod extensions;
mod packages;

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

/// Runs the install/update/remove commands exposed by the bundled CLI.
#[allow(unsafe_code, reason = "the stable C ABI requires an unmangled export")]
#[unsafe(no_mangle)]
pub extern "C" fn kineticPackageMain() -> i32 {
    packages::run()
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
