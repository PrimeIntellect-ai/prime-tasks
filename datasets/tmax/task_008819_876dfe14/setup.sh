#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential cargo
    pip3 install pytest

    mkdir -p /home/user/sysmon/src
    mkdir -p /home/user/sysmon/tests
    mkdir -p /home/user/sysmon/lib

    # Create the dummy C library
    cat << 'EOF' > /home/user/sysmon/lib/systools.c
#include <stdint.h>
int32_t process_c(const uint8_t* data, uintptr_t len) {
    return (int32_t)len;
}
EOF
    gcc -c /home/user/sysmon/lib/systools.c -o /home/user/sysmon/lib/systools.o
    ar rcs /home/user/sysmon/lib/libsystools.a /home/user/sysmon/lib/systools.o

    # Create the Rust project files
    cat << 'EOF' > /home/user/sysmon/Cargo.toml
[package]
name = "sysmon"
version = "0.1.0"
edition = "2021"
EOF

    cat << 'EOF' > /home/user/sysmon/build.rs
fn main() {
    println!("cargo:rustc-link-lib=static=systools");
    // BUG: Missing the search path for the lib directory
    // println!("cargo:rustc-link-search=native=lib");
}
EOF

    cat << 'EOF' > /home/user/sysmon/src/lib.rs
extern "C" { 
    fn process_c(data: *const u8, len: usize) -> i32; 
}

pub fn process_input(data: &[u8]) -> Result<i32, &'static str> {
    if data.is_empty() { 
        return Ok(0); 
    }
    // BUG: Panics instead of returning Err
    if data[0] == 0xFF { 
        panic!("Invalid header"); 
    }
    unsafe { 
        Ok(process_c(data.as_ptr(), data.len())) 
    }
}
EOF

    # Create the crash log
    cat << 'EOF' > /home/user/crash.log
INFO: Fuzzer started
INFO: Run 100
[FUZZER] Panic triggered by input: ff0a0b
INFO: Run 200
INFO: Run 300
[FUZZER] Panic triggered by input: ff112233
INFO: Fuzzer finished
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
