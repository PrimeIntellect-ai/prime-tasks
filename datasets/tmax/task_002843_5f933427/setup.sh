#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential cargo
    pip3 install pytest

    mkdir -p /home/user/project/clib
    mkdir -p /home/user/project/rust_wrapper/src

    cat << 'EOF' > /home/user/project/clib/c_lib.c
#include <stdlib.h>
#include <string.h>

char* get_c_message() {
    char* msg = malloc(50);
    strcpy(msg, "Hello from C");
    return msg;
}

void free_c_message(char* msg) {
    free(msg);
}
EOF

    cat << 'EOF' > /home/user/project/rust_wrapper/Cargo.toml
[package]
name = "rust_wrapper"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[dependencies]
EOF

    cat << 'EOF' > /home/user/project/rust_wrapper/build.rs
fn main() {
    // BUG: Missing the search path for the C library
    println!("cargo:rustc-link-lib=c_lib");
}
EOF

    cat << 'EOF' > /home/user/project/rust_wrapper/src/lib.rs
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

extern "C" {
    fn get_c_message() -> *mut c_char;
    fn free_c_message(msg: *mut c_char);
}

#[no_mangle]
pub extern "C" fn get_combined_message() -> *mut c_char {
    let base_msg = unsafe {
        let ptr = get_c_message();
        let s = CStr::from_ptr(ptr).to_string_lossy().into_owned();
        free_c_message(ptr);
        s
    };

    let combined = format!("{} and Rust!", base_msg);
    let c_string = CString::new(combined).unwrap();

    // BUG: Returns a pointer to the inner buffer, but c_string is dropped here
    c_string.as_ptr() as *mut c_char
}
EOF

    cat << 'EOF' > /home/user/project/expected.txt
Apple
Hello from C and Rust!
Mango
Zebra
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/project
    chmod -R 777 /home/user
