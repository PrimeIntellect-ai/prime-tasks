#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/workspace/rust_part/src
    mkdir -p /home/user/workspace/c_part

    cat << 'EOF' > /home/user/workspace/rust_part/Cargo.toml
[package]
name = "rust_part"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]
EOF

    cat << 'EOF' > /home/user/workspace/rust_part/src/lib.rs
use std::os::raw::c_char;
use std::ffi::CStr;

struct ChecksumHelper<'a> {
    data: &'a str,
}

impl<'a> ChecksumHelper<'a> {
    // Missing lifetime specifier causes compilation error
    fn new(d: &str) -> ChecksumHelper {
        ChecksumHelper { data: d }
    }

    fn compute(&self) -> u32 {
        self.data.bytes().map(|b| b as u32).sum()
    }
}

#[no_mangle]
pub extern "C" fn rust_checksum(data: *const c_char) -> u32 {
    let c_str = unsafe { CStr::from_ptr(data) };
    let str_slice = c_str.to_str().unwrap();
    let helper = ChecksumHelper::new(str_slice);
    helper.compute()
}
EOF

    cat << 'EOF' > /home/user/workspace/c_part/c_checksum.c
#include <stdint.h>

uint32_t c_checksum(const char* data) {
    uint32_t hash = 5381;
    int c;
    while ((c = *data++)) {
        hash = ((hash << 5) + hash) + c; /* hash * 33 + c */
    }
    return hash;
}
EOF

    cat << 'EOF' > /home/user/workspace/c_part/Makefile
libcchecksum.so: c_checksum.o
	gcc -shared -o libcchecksum.so c_checksum.o

c_checksum.o: c_checksum.c
	gcc -c c_checksum.c
EOF

    chmod -R 777 /home/user
