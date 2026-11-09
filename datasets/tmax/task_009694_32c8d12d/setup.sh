#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc cargo
    pip3 install pytest

    mkdir -p /home/user/app
    cat << 'EOF' > /home/user/app/input.json
[
  {"id": 1, "payload": "hello"},
  {"id": 2, "payload": "world"},
  {"id": 3, "payload": "polyglot"}
]
EOF

    cd /home/user/app/
    cargo new --lib rust_transform

    cat << 'EOF' >> /home/user/app/rust_transform/Cargo.toml

[lib]
crate-type = ["cdylib"]
EOF

    cat << 'EOF' > /home/user/app/rust_transform/src/lib.rs
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn reverse_string(input: *const c_char) -> *const c_char {
    let c_str = unsafe { CStr::from_ptr(input) };
    let str_slice = c_str.to_str().unwrap();
    let reversed: String = str_slice.chars().rev().collect();
    // Lifetime error: returning pointer to local variable
    let c_reversed = CString::new(reversed).unwrap();
    c_reversed.as_ptr() 
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
