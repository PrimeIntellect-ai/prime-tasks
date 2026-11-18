#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential rustc cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Initialize Rust project
    cargo new --lib /home/user/engine

    # Update Cargo.toml
    cat << 'EOF' > /home/user/engine/Cargo.toml
[package]
name = "engine"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]
EOF

    # Create lib.rs with the intentional bug
    cat << 'EOF' > /home/user/engine/src/lib.rs
use std::os::raw::c_char;
use std::ffi::{CStr, CString};

#[no_mangle]
pub extern "C" fn encode_rle(input: *const c_char) -> *mut c_char {
    let c_str = unsafe {
        assert!(!input.is_null());
        CStr::from_ptr(input)
    };
    let s = c_str.to_str().unwrap();

    let mut res = String::new();
    let mut chars = s.chars().peekable();

    while let Some(c) = chars.next() {
        let mut n = 1;
        while chars.peek() == Some(&c) {
            n += 1;
            chars.next();
        }
        res.push_str(&format!("{}{}", c, n));
    }

    let c_res = CString::new(res).unwrap();
    // BUG: Returning pointer to dropped CString
    c_res.as_ptr() as *mut c_char
}
EOF

    # Create data.txt
    cat << 'EOF' > /home/user/data.txt
AAAAAABBBBBBBCCCCdddddddddddddd🔥🔥🔥🔥❄️❄️❄️
EOF

    chmod -R 777 /home/user
