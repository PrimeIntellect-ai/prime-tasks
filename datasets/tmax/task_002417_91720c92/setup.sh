#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install task-specific dependencies
    apt-get install -y gcc sqlite3 cargo

    # Create user
    useradd -m -s /bin/bash user || true

    # Create project directories
    mkdir -p /home/user/waf_project/c_src
    mkdir -p /home/user/waf_project/rust_app/src

    # Create C source files
    cat << 'EOF' > /home/user/waf_project/c_src/parser.h
#ifndef PARSER_H
#define PARSER_H
void url_decode(const char *src, char *dest);
#endif
EOF

    cat << 'EOF' > /home/user/waf_project/c_src/parser.c
#include "parser.h"
#include <ctype.h>

// Helper to convert hex char to int
int hex_to_int(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return 0;
}

void url_decode(const char *src, char *dest) {
    while (*src) {
        if (*src == '%') {
            // TODO: missing hex decoding logic
            // src++; ...
        } else if (*src == '+') {
            *dest++ = ' ';
            src++;
        } else {
            *dest++ = *src++;
        }
    }
    *dest = '\0';
}
EOF

    # Create Rust source files
    cat << 'EOF' > /home/user/waf_project/rust_app/Cargo.toml
[package]
name = "waf_app"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/waf_project/rust_app/build.rs
fn main() {
    println!("cargo:rustc-link-search=native=../c_src");
    println!("cargo:rustc-link-lib=dylib=parser");
}
EOF

    cat << 'EOF' > /home/user/waf_project/rust_app/src/main.rs
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::env;

extern "C" {
    fn url_decode(src: *const c_char, dest: *mut c_char);
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        println!("No payload provided.");
        return;
    }

    let input = &args[1];

    // BUG: dangling pointer here
    let src_ptr = CString::new(input.as_str()).unwrap().as_ptr();

    let mut dest_buf: Vec<u8> = vec![0; input.len() + 1];
    let dest_ptr = dest_buf.as_mut_ptr() as *mut c_char;

    unsafe {
        url_decode(src_ptr, dest_ptr);
        let result = CStr::from_ptr(dest_ptr).to_string_lossy();
        println!("Decoded: {}", result);
    }
}
EOF

    # Create build script
    cat << 'EOF' > /home/user/waf_project/build.sh
#!/bin/bash
cd /home/user/waf_project/c_src
gcc -shared -fPIC -o libparser.so parser.c

cd /home/user/waf_project/rust_app
# BUG: needs LD_LIBRARY_PATH export or similar to run successfully
cargo build
EOF
    chmod +x /home/user/waf_project/build.sh

    # Setup database
    sqlite3 /home/user/waf_project/rules.db "CREATE TABLE rules (id INTEGER PRIMARY KEY, pattern TEXT);"
    sqlite3 /home/user/waf_project/rules.db "INSERT INTO rules (pattern) VALUES ('<script>');"

    # Set permissions
    chmod -R 777 /home/user
