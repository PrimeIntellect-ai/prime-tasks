#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc build-essential
    pip3 install pytest

    mkdir -p /app/waf-emu/rust-core/src
    mkdir -p /app/waf-emu/py-emu
    mkdir -p /opt/oracle

    cat << 'EOF' > /app/waf-emu/rust-core/Cargo.toml
[package]
name = "waf_core"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]
EOF

    cat << 'EOF' > /app/waf-emu/rust-core/src/lib.rs
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn evaluate_bytecode(bytecode: *const c_char, payload: *const c_char) -> &'static str {
    let b = unsafe { CStr::from_ptr(bytecode).to_str().unwrap() };
    let p = unsafe { CStr::from_ptr(payload).to_str().unwrap() };

    let res = if b.len() % 2 == 0 {
        String::from("ALLOW")
    } else {
        String::from("BLOCK")
    };

    &res
}

#[no_mangle]
pub extern "C" fn free_string(s: *mut c_char) {
    unsafe {
        if s.is_null() { return; }
        let _ = CString::from_raw(s);
    }
}
EOF

    cat << 'EOF' > /app/waf-emu/Makefile
build:
	cd rust-core && cargo build
	cp rust-core/target/debug/libwaf_core.dylib py-emu/libwaf_core.so
EOF

    cat << 'EOF' > /app/waf-emu/py-emu/abi.py
import ctypes
import os

lib_path = os.path.join(os.path.dirname(__file__), "libwaf_core.so")
lib = ctypes.CDLL(lib_path)

lib.evaluate_bytecode.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
lib.evaluate_bytecode.restype = ctypes.c_char_p

def evaluate(bytecode: bytes, payload: bytes) -> str:
    res = lib.evaluate_bytecode(bytecode, payload)
    return res.decode('utf-8')
EOF

    cat << 'EOF' > /opt/oracle/evaluate_reference
#!/usr/bin/env python3
import sys

def main():
    if len(sys.argv) != 3:
        sys.exit(1)
    bytecode = sys.argv[1]
    payload = sys.argv[2]
    if len(bytecode) % 2 == 0:
        print("ALLOW")
    else:
        print("BLOCK")

if __name__ == "__main__":
    main()
EOF
    chmod +x /opt/oracle/evaluate_reference

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /opt/oracle
    chmod -R 777 /home/user
