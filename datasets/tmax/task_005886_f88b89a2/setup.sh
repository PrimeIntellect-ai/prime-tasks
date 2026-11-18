#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create legacy input
    echo -n "eyJsZWdhY3lfdXNlciI6ICJib2IxMjMiLCAiZGF0YV9wYXlsb2FkIjogImFjdGl2ZSJ9" > /home/user/legacy_input.txt

    # Create Rust project
    mkdir -p /home/user/rust_parser/src

    cat << 'EOF' > /home/user/rust_parser/Cargo.toml
[package]
name = "rust_parser"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[dependencies]
serde_json = "1.0"
EOF

    cat << 'EOF' > /home/user/rust_parser/src/lib.rs
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use serde_json::Value;

#[no_mangle]
pub extern "C" fn migrate_schema(input: *const c_char) -> *mut c_char {
    if input.is_null() {
        return std::ptr::null_mut();
    }

    let c_str = unsafe { CStr::from_ptr(input) };
    let json_str = c_str.to_str().unwrap_or("{}");

    let parsed: Value = serde_json::from_str(json_str).unwrap_or(Value::Null);

    // Schema migration: wrap in a new v2 structure
    let migrated = serde_json::json!({
        "schema_version": "v2",
        "user_id": parsed["legacy_user"],
        "status": parsed["data_payload"]
    });

    let result_str = migrated.to_string();
    let c_result = CString::new(result_str).unwrap();

    // BUG: Returning a pointer to a temporary CString that gets dropped at the end of the function
    c_result.as_ptr() as *mut c_char
}

#[no_mangle]
pub extern "C" fn free_string(s: *mut c_char) {
    if s.is_null() { return; }
    unsafe {
        let _ = CString::from_raw(s);
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
