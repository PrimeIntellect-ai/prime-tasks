#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make rustc cargo time
    pip3 install pytest

    mkdir -p /home/user/data_pipeline/c_lib
    mkdir -p /home/user/data_pipeline/rust_app/src

    cat << 'EOF' > /home/user/data_pipeline/c_lib/filter.c
#include <string.h>
#include <stdlib.h>

char* store[100];
int count = 0;

void filter_add(const char* s) {
    if (count < 100) {
        store[count++] = strdup(s);
    }
}

int filter_check(const char* s) {
    for (int i = 0; i < count; i++) {
        if (strcmp(store[i], s) == 0) return 1;
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/data_pipeline/c_lib/Makefile
all: filter.o
	# INTENTIONAL BUG: Not building the archive libfilter.a
	gcc -c filter.c -o filter.o
EOF

    cat << 'EOF' > /home/user/data_pipeline/rust_app/Cargo.toml
[package]
name = "rust_app"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/data_pipeline/rust_app/build.rs
fn main() {
    // INTENTIONAL BUG: Missing link instructions
    // println!("cargo:rustc-link-search=native=../c_lib");
    // println!("cargo:rustc-link-lib=static=filter");
}
EOF

    cat << 'EOF' > /home/user/data_pipeline/rust_app/src/main.rs
use std::ffi::CString;
use std::os::raw::c_char;
use std::fs;
use std::env;

extern "C" {
    fn filter_add(s: *const c_char);
    fn filter_check(s: *const c_char) -> i32;
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: {} <file>", args[0]);
        std::process::exit(1);
    }

    unsafe {
        // INTENTIONAL BUG: inline as_ptr() causes CString drop
        filter_add(CString::new("apple").unwrap().as_ptr());
        filter_add(CString::new("banana").unwrap().as_ptr());
    }

    let contents = fs::read_to_string(&args[1]).unwrap();
    for line in contents.lines() {
        let c_line = CString::new(line).unwrap();
        unsafe {
            if filter_check(c_line.as_ptr()) == 1 {
                println!("MATCH: {}", line);
            }
        }
    }
}
EOF

    cat << 'EOF' > /home/user/data.txt
cherry
apple
grape
banana
orange
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
