#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl cargo rustc
    pip3 install pytest websockets

    mkdir -p /home/user/rust_hasher/src
    mkdir -p /home/user/artifacts

    cat << 'EOF' > /home/user/rust_hasher/Cargo.toml
[package]
name = "rust_hasher"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]
EOF

    cat << 'EOF' > /home/user/rust_hasher/src/lib.rs
use std::ffi::CString;
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn calculate_artifact_checksum(data: *const u8, data_len: usize) -> *const c_char {
    let slice = unsafe { std::slice::from_raw_parts(data, data_len) };
    let mut s1 = 1u32;
    let mut s2 = 0u32;
    for &byte in slice {
        s1 = (s1 + byte as u32) % 65521;
        s2 = (s2 + s1) % 65521;
    }
    let hash = (s2 << 16) | s1;
    let result = format!("{:08x}", hash);

    // BUG: Returning a pointer to a temporary CString
    let c_str = CString::new(result).unwrap();
    c_str.as_ptr()
}

#[no_mangle]
pub extern "C" fn free_checksum(ptr: *mut c_char) {
    if ptr.is_null() { return; }
    unsafe { let _ = CString::from_raw(ptr); }
}
EOF

    echo "File A contents" > /home/user/artifacts/fileA.txt
    echo "File B contents" > /home/user/artifacts/fileB.txt
    echo "File C contents" > /home/user/artifacts/fileC.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
