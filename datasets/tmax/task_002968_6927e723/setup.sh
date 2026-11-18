#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    tesseract-ocr \
    nginx \
    socat \
    build-essential \
    cargo \
    rustc \
    imagemagick

pip3 install pytest

mkdir -p /app/c_src /app/rust_src/src

cat << 'EOF' > /app/c_src/libocr.c
#include <stdio.h>
#include <stdlib.h>
// missing string.h and other includes
char* extract_text(const char* image_path) {
    char cmd[256];
    sprintf(cmd, "tesseract %s stdout 2>/dev/null", image_path);
    FILE* fp = popen(cmd, "r");
    if (!fp) return NULL;
    char* result = malloc(1024);
    int bytes_read = fread(result, 1, 1023, fp);
    result[bytes_read] = '\0';
    pclose(fp);
    return result;
}
EOF

cat << 'EOF' > /app/c_src/Makefile
# Broken Makefile for shared library
all:
	gcc -c libocr.c
	gcc -o libocr.so libocr.o
EOF

cat << 'EOF' > /app/rust_src/Cargo.toml
[package]
name = "rust_ocr"
version = "0.1.0"
edition = "2021"

[dependencies]
libc = "0.2"
EOF

cat << 'EOF' > /app/rust_src/src/main.rs
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::env;

extern "C" {
    fn extract_text(image_path: *const c_char) -> *mut c_char;
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        return;
    }
    let path = CString::new(args[1].clone()).unwrap();
    unsafe {
        let c_ptr = extract_text(path.as_ptr());
        // broken lifetime and borrow handling
        let result = CStr::from_ptr(c_ptr).to_str().unwrap();
        println!("{}", result);
    }
}
EOF

convert -size 400x100 xc:white -fill black -pointsize 24 -draw "text 10,50 'ORDER_ID: 88921'" /app/test_receipt.png

useradd -m -s /bin/bash user || true
chmod -R 777 /app
chmod -R 777 /home/user
