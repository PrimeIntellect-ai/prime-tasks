#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo build-essential
    pip3 install pytest

    mkdir -p /home/user/ws_encoder_api/c_src
    mkdir -p /home/user/ws_encoder_api/src
    mkdir -p /home/user/ws_encoder_api/tests

    cat << 'EOF' > /home/user/ws_encoder_api/Cargo.toml
[package]
name = "ws_encoder_api"
version = "0.1.0"
edition = "2021"

[dependencies]
libc = "0.2"

[build-dependencies]
cc = "1.0"
EOF

    touch /home/user/ws_encoder_api/build.rs

    cat << 'EOF' > /home/user/ws_encoder_api/c_src/hex_encoder.h
#ifndef HEX_ENCODER_H
#define HEX_ENCODER_H
#include <stddef.h>
char* encode_hex(const unsigned char* input, size_t len);
void free_hex(char* ptr);
#endif
EOF

    cat << 'EOF' > /home/user/ws_encoder_api/c_src/hex_encoder.c
#include "hex_encoder.h"
#include <stdlib.h>
#include <stdio.h>

char* encode_hex(const unsigned char* input, size_t len) {
    // BUG: len * 2 does not account for the null terminator.
    char* output = (char*)malloc(len * 2);
    if (!output) return NULL;

    for (size_t i = 0; i < len; i++) {
        sprintf(output + (i * 2), "%02x", input[i]);
    }
    // output[len * 2] = '\0'; // Missing null termination
    return output;
}

void free_hex(char* ptr) {
    free(ptr);
}
EOF

    cat << 'EOF' > /home/user/ws_encoder_api/src/lib.rs
pub mod rate_limit;

use libc::{c_char, c_uchar, size_t};
use std::ffi::CStr;

extern "C" {
    fn encode_hex(input: *const c_uchar, len: size_t) -> *mut c_char;
    fn free_hex(ptr: *mut c_char);
}

pub fn encode_data(data: &[u8]) -> String {
    unsafe {
        let c_ptr = encode_hex(data.as_ptr(), data.len() as size_t);
        if c_ptr.is_null() {
            panic!("Memory allocation failed in C");
        }
        let c_str = CStr::from_ptr(c_ptr);
        let result = c_str.to_string_lossy().into_owned();
        free_hex(c_ptr);
        result
    }
}
EOF

    cat << 'EOF' > /home/user/ws_encoder_api/src/rate_limit.rs
use std::collections::HashMap;

pub struct RateLimiter {
    counts: HashMap<u32, u32>,
}

impl RateLimiter {
    pub fn new() -> Self {
        Self {
            counts: HashMap::new(),
        }
    }

    /// Checks if a client is allowed to send a message.
    /// Max 3 messages allowed. Returns true if allowed, false if rejected.
    pub fn check_and_record(&mut self, client_id: u32) -> bool {
        // TODO: Agent must implement this.
        true
    }
}
EOF

    cat << 'EOF' > /home/user/ws_encoder_api/tests/integration_test.rs
use ws_encoder_api::{encode_data, rate_limit::RateLimiter};

#[test]
fn test_hex_encoding_safety() {
    let data = b"Hello WebSocket!";
    let encoded = encode_data(data);
    assert_eq!(encoded, "48656c6c6f20576562536f636b657421");

    let large_data = vec![0xAB; 1000];
    let encoded_large = encode_data(&large_data);
    assert_eq!(encoded_large.len(), 2000);
}

#[test]
fn test_rate_limiter() {
    let mut limiter = RateLimiter::new();

    assert_eq!(limiter.check_and_record(1), true);
    assert_eq!(limiter.check_and_record(1), true);
    assert_eq!(limiter.check_and_record(1), true);
    assert_eq!(limiter.check_and_record(1), false); // 4th request should fail

    assert_eq!(limiter.check_and_record(2), true); // New client should pass
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/ws_encoder_api
    chmod -R 777 /home/user
