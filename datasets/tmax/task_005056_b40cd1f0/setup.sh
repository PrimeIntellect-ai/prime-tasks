#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo gcc
    pip3 install pytest

    mkdir -p /home/user/tinyvm/src /home/user/tinyvm/tests
    cd /home/user/tinyvm

    cat << 'EOF' > Cargo.toml
[package]
name = "tinyvm"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib", "rlib"]

[dev-dependencies]
proptest = "1.0"
rand = "0.8"
EOF

    cat << 'EOF' > src/lib.rs
pub mod decoder;

#[no_mangle]
pub extern "C" fn execute_hex(hex_str: *const std::os::raw::c_char) -> u32 {
    let c_str = unsafe { std::ffi::CStr::from_ptr(hex_str) };
    let hex_string = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let bytecode = match decoder::decode_hex(hex_string) {
        Some(b) => b,
        None => return 0,
    };

    let mut stack: Vec<u32> = Vec::new();
    let mut pc = 0;

    while pc < bytecode.len() {
        match bytecode[pc] {
            0x01 => {
                if pc + 1 < bytecode.len() {
                    stack.push(bytecode[pc + 1] as u32);
                    pc += 2;
                } else {
                    break;
                }
            }
            0x02 => {
                if stack.len() >= 2 {
                    let a = stack.pop().unwrap();
                    let b = stack.pop().unwrap();
                    stack.push(a + b);
                }
                pc += 1;
            }
            0x03 => {
                if stack.len() >= 2 {
                    let a = stack.pop().unwrap();
                    let b = stack.pop().unwrap();
                    stack.push(b.wrapping_sub(a));
                }
                pc += 1;
            }
            0xFF => {
                return stack.pop().unwrap_or(0);
            }
            _ => {
                pc += 1;
            }
        }
    }
    0
}

pub fn execute_raw(bytecode: &[u8]) -> u32 {
    let mut stack: Vec<u32> = Vec::new();
    let mut pc = 0;

    while pc < bytecode.len() {
        match bytecode[pc] {
            0x01 => {
                if pc + 1 < bytecode.len() {
                    stack.push(bytecode[pc + 1] as u32);
                    pc += 2;
                } else {
                    break;
                }
            }
            0x02 => {
                if stack.len() >= 2 {
                    let a = stack.pop().unwrap();
                    let b = stack.pop().unwrap();
                    stack.push(a + b);
                }
                pc += 1;
            }
            0x03 => {
                if stack.len() >= 2 {
                    let a = stack.pop().unwrap();
                    let b = stack.pop().unwrap();
                    stack.push(b.wrapping_sub(a));
                }
                pc += 1;
            }
            0xFF => {
                return stack.pop().unwrap_or(0);
            }
            _ => {
                pc += 1;
            }
        }
    }
    0
}
EOF

    cat << 'EOF' > src/decoder.rs
pub fn decode_hex(s: &str) -> Option<Vec<u8>> {
    if s.len() % 2 != 0 {
        return None;
    }

    let mut result = Vec::with_capacity(s.len() / 2);
    let bytes = s.as_bytes();

    for i in (0..bytes.len()).step_by(2) {
        let high = hex_val(bytes[i])?;
        let low = hex_val(bytes[i + 1])?;
        result.push((high << 4) | low);
    }

    Some(result)
}

fn hex_val(c: u8) -> Option<u8> {
    match c {
        b'0'..=b'9' => Some(c - b'0'),
        b'a'..=b'f' => Some(c - b'a' + 10),
        // BUG: Missing uppercase support which causes random test failures
        _ => None,
    }
}
EOF

    cat << 'EOF' > tests/prop_test.rs
use proptest::prelude::*;
use std::ffi::CString;
use tinyvm::{execute_raw, execute_hex};

proptest! {
    #[test]
    fn test_hex_execution_matches_raw(
        bytecode in proptest::collection::vec(any::<u8>(), 0..100),
        use_uppercase in any::<bool>()
    ) {
        let mut hex_str = String::new();
        for b in &bytecode {
            if use_uppercase {
                hex_str.push_str(&format!("{:02X}", b));
            } else {
                hex_str.push_str(&format!("{:02x}", b));
            }
        }

        let c_str = CString::new(hex_str).unwrap();
        let result_hex = execute_hex(c_str.as_ptr());
        let result_raw = execute_raw(&bytecode);

        assert_eq!(result_hex, result_raw);
    }
}
EOF

    cat << 'EOF' > runner.c
#include <stdio.h>
#include <stdint.h>

extern uint32_t execute_hex(const char* hex_str);

int main(int argc, char** argv) {
    if (argc < 2) {
        printf("Usage: %s <hex_string>\n", argv[0]);
        return 1;
    }

    uint32_t res = execute_hex(argv[1]);
    printf("Result: %u\n", res);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
