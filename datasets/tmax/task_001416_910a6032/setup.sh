#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential rustc cargo upx-ucl
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/polyglot-sanitizer/c_src
    mkdir -p /home/user/polyglot-sanitizer/rust_src/src
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Create C source files
    cat << 'EOF' > /home/user/polyglot-sanitizer/c_src/filter.h
#ifndef FILTER_H
#define FILTER_H
#include <stddef.h>

// Returns 1 if valid and safe, 0 if malicious or invalid UTF-8.
int validate_and_check(const char* input, size_t len);

#endif
EOF

    cat << 'EOF' > /home/user/polyglot-sanitizer/c_src/filter.c
#include "filter.h"
#include <string.h>

int validate_and_check(const char* input, size_t len) {
    // BUG: Missing strict UTF-8 validation
    // BUG: Buffer overflow vulnerability in loop condition
    for (size_t i = 0; i <= len; i++) {
        if (input[i] == '<') {
            if (strncmp(&input[i], "<script>", 8) == 0) return 0;
        }
        if (input[i] == 'e') {
            if (strncmp(&input[i], "exec(", 5) == 0) return 0;
        }
    }
    return 1;
}
EOF

    # Create Rust source files
    cat << 'EOF' > /home/user/polyglot-sanitizer/rust_src/Cargo.toml
[package]
name = "sanitizer_cli"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/polyglot-sanitizer/rust_src/src/main.rs
use std::env;
use std::fs;
use std::ffi::CString;
use std::os::raw::c_char;

extern "C" {
    fn validate_and_check(input: *const c_char, len: usize) -> i32;
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        std::process::exit(1);
    }

    let content = fs::read(&args[1]).unwrap();

    // Borrow checker/FFI bug: CString::new might fail on inner nulls, 
    // and passing as_ptr() without keeping CString alive drops it.
    let c_str = CString::new(content.clone()).unwrap().as_ptr();

    let is_valid = unsafe {
        validate_and_check(c_str, content.len())
    };

    if is_valid == 1 {
        print!("{}", String::from_utf8_lossy(&content));
        std::process::exit(0);
    } else {
        std::process::exit(1);
    }
}
EOF

    # Create oracle C source and compile it
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int is_valid_utf8(const char *s, size_t len) {
    size_t i = 0;
    while (i < len) {
        unsigned char c = s[i];
        if (c <= 0x7F) {
            i += 1;
        } else if ((c & 0xE0) == 0xC0) {
            if (i + 1 >= len || (s[i+1] & 0xC0) != 0x80) return 0;
            i += 2;
        } else if ((c & 0xF0) == 0xE0) {
            if (i + 2 >= len || (s[i+1] & 0xC0) != 0x80 || (s[i+2] & 0xC0) != 0x80) return 0;
            i += 3;
        } else if ((c & 0xF8) == 0xF0) {
            if (i + 3 >= len || (s[i+1] & 0xC0) != 0x80 || (s[i+2] & 0xC0) != 0x80 || (s[i+3] & 0xC0) != 0x80) return 0;
            i += 4;
        } else {
            return 0;
        }
    }
    return 1;
}

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;
    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *buf = malloc(len + 1);
    if (!buf) { fclose(f); return 1; }
    fread(buf, 1, len, f);
    buf[len] = '\0';
    fclose(f);

    if (!is_valid_utf8(buf, len)) { free(buf); return 1; }
    if (strstr(buf, "<script>") != NULL) { free(buf); return 1; }
    if (strstr(buf, "exec(") != NULL) { free(buf); return 1; }

    printf("%s", buf);
    free(buf);
    return 0;
}
EOF

    gcc -O2 -s -o /app/sanitizer_oracle /tmp/oracle.c
    upx /app/sanitizer_oracle || true
    chmod +x /app/sanitizer_oracle

    # Create corpus files
    echo -n "Hello world, this is a clean file." > /app/corpus/clean/test1.txt
    echo -n "Another perfectly fine text file." > /app/corpus/clean/test2.txt

    echo -n "This file contains a <script> tag." > /app/corpus/evil/test1.txt
    printf "\xff\xfe\xfd" > /app/corpus/evil/test2.txt
    echo -n "Some text and then exec(something)" > /app/corpus/evil/test3.txt

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
