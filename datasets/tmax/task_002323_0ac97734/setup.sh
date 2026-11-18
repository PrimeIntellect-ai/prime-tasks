#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/release_prep/rust_ffi/src

    cat << 'EOF' > /home/user/release_prep/rust_ffi/Cargo.toml
[package]
name = "rust_ffi"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]
EOF

    cat << 'EOF' > /home/user/release_prep/rust_ffi/src/lib.rs
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn generate_release_tag(version: *const c_char) -> *mut c_char {
    let v = unsafe { CStr::from_ptr(version).to_str().unwrap() };
    let tag = format!("RELEASE-{}", v);

    let borrowed_c_str: &CStr;
    {
        let c_str = CString::new(tag).unwrap();
        borrowed_c_str = c_str.as_c_str(); // ERROR: c_str dropped here while borrowed
    }

    borrowed_c_str.as_ptr() as *mut c_char
}
EOF

    cat << 'EOF' > /home/user/release_prep/test_release.py
import pytest
import ctypes
import os
from unittest.mock import Mock

@pytest.fixture
def release_lib():
    # TODO: Replace this mock setup with actual FFI loading using ctypes.CDLL
    # Ensure you set argtypes and restype for generate_release_tag appropriately.
    mock_lib = Mock()
    mock_lib.generate_release_tag = Mock(return_value=b"RELEASE-2.4.5")
    yield mock_lib

def test_tag_generation(release_lib):
    result = release_lib.generate_release_tag(b"2.4.5")
    # Using ctypes with restype = c_char_p returns bytes.
    assert result == b"RELEASE-2.4.5"
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/release_prep
    chmod -R 777 /home/user
