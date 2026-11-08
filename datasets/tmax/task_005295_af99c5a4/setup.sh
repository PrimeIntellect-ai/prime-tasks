#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make rustc cargo
    pip3 install --no-cache-dir pytest fastapi==0.103.1 uvicorn==0.23.2

    mkdir -p /home/user/workspace/c_lib
    mkdir -p /home/user/workspace/rust_lib/src
    mkdir -p /home/user/workspace/python_api

    cat << 'EOF' > /home/user/workspace/c_lib/dataproc.c
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

char* process_text(const char* input) {
    if (!input) return NULL;
    char* result = malloc(strlen(input) + 10);
    sprintf(result, "PROCESSED:%s", input);
    return result;
}

void free_text(char* ptr) {
    if (ptr) {
        free(ptr);
    }
}
EOF

    cat << 'EOF' > /home/user/workspace/c_lib/Makefile
all:
	gcc -shared -fPIC -o libdataproc.so dataproc.c
EOF

    cat << 'EOF' > /home/user/workspace/rust_lib/Cargo.toml
[package]
name = "rustffi"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]
EOF

    cat << 'EOF' > /home/user/workspace/rust_lib/src/lib.rs
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

extern "C" {
    fn process_text(input: *const c_char) -> *mut c_char;
    fn free_text(ptr: *mut c_char);
}

#[no_mangle]
pub extern "C" fn process_via_rust(input: *const c_char) -> *const c_char {
    unsafe {
        let result_ptr = process_text(input);

        // BUG 1: Borrow checker / Lifetime issue.
        // Trying to convert to CStr, then String, then CString, and returning the internal pointer of a dropped CString.
        let c_str = CStr::from_ptr(result_ptr);
        let rust_str = c_str.to_str().unwrap().to_string() + "_RUSTIFIED";

        let new_c_string = CString::new(rust_str).unwrap();

        // BUG 2: Memory leak - result_ptr from C is never freed.
        // free_text(result_ptr); // This is missing

        // BUG 1 part 2: returning pointer to local CString that gets dropped
        new_c_string.as_ptr() 
        // Correct fix: new_c_string.into_raw()
        // And then need another exported function to free the rust-allocated string, but for this task, 
        // returning new_c_string.into_raw() and freeing the C pointer is sufficient.
    }
}

#[no_mangle]
pub extern "C" fn free_rust_string(ptr: *mut c_char) {
    unsafe {
        if !ptr.is_null() {
            let _ = CString::from_raw(ptr);
        }
    }
}
EOF

    cat << 'EOF' > /home/user/workspace/python_api/requirements.txt
fastapi==0.103.1
uvicorn==0.23.2
EOF

    cat << 'EOF' > /home/user/workspace/python_api/app.py
from fastapi import FastAPI
import ctypes
import os

app = FastAPI()

# Trying to load the Rust library
# BUG: Linking issue - LD_LIBRARY_PATH needs to include c_lib, or it must be loaded explicitly.
rust_lib_path = os.path.abspath("../rust_lib/target/debug/librustffi.so")
rust_lib = ctypes.CDLL(rust_lib_path)

rust_lib.process_via_rust.argtypes = [ctypes.c_char_p]
rust_lib.process_via_rust.restype = ctypes.POINTER(ctypes.c_char)
rust_lib.free_rust_string.argtypes = [ctypes.POINTER(ctypes.c_char)]

@app.get("/process")
def process(text: str):
    input_bytes = text.encode('utf-8')
    res_ptr = rust_lib.process_via_rust(input_bytes)
    res_str = ctypes.cast(res_ptr, ctypes.c_char_p).value.decode('utf-8')
    rust_lib.free_rust_string(res_ptr)
    return {"result": res_str}

# Missing /stats endpoint
EOF

    cd /home/user/workspace/c_lib && make

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
