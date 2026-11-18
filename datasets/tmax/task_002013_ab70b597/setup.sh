#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc gcc nginx curl
    pip3 install pytest

    mkdir -p /home/user/project/c_lib
    mkdir -p /home/user/project/emulator/src
    mkdir -p /home/user/project/nginx_temp

    # C Library
    cat << 'EOF' > /home/user/project/c_lib/crypto_dummy.c
#include "crypto_dummy.h"
#include <string.h>
int verify_bytecode(const char* bytecode) {
    if (strcmp(bytecode, "1") == 0) return 1;
    return 0;
}
EOF

    cat << 'EOF' > /home/user/project/c_lib/crypto_dummy.h
#ifndef CRYPTO_DUMMY_H
#define CRYPTO_DUMMY_H
int verify_bytecode(const char* bytecode);
#endif
EOF

    # Rust Emulator
    cat << 'EOF' > /home/user/project/emulator/Cargo.toml
[package]
name = "emulator"
version = "0.1.0"
edition = "2021"

[dependencies]
tiny_http = "0.12"
EOF

    cat << 'EOF' > /home/user/project/emulator/build.rs
fn main() {
    // Intentional bug: missing the library search path
    println!("cargo:rustc-link-lib=crypto_dummy");
}
EOF

    cat << 'EOF' > /home/user/project/emulator/src/main.rs
use std::ffi::CString;
use std::os::raw::c_char;
use tiny_http::{Server, Response};

extern "C" {
    fn verify_bytecode(bytecode: *const c_char) -> std::os::raw::c_int;
}

struct Emulator {
    memory: Vec<u8>,
}

impl Emulator {
    fn new() -> Self {
        Emulator { memory: vec![0; 256] }
    }

    fn load(&mut self, code: &str) {
        self.memory[0] = if code == "1" { 1 } else { 0 };
    }

    fn run(&mut self) -> String {
        let code = if self.memory[0] == 1 { "1" } else { "0" };
        let c_str = CString::new(code).unwrap();

        let valid = unsafe { verify_bytecode(c_str.as_ptr()) };

        // Intentional borrow checker error: borrowing self mutably while holding a mutable reference to self.memory
        let mem_ref = &mut self.memory;
        self.do_something_else(); 
        mem_ref[1] = 1;

        if valid == 1 {
            "EXECUTION_SUCCESS".to_string()
        } else {
            "EXECUTION_FAILED".to_string()
        }
    }

    fn do_something_else(&mut self) {
        // dummy
    }
}

fn main() {
    let server = Server::http("127.0.0.1:9000").unwrap();
    println!("Emulator listening on port 9000");

    for request in server.incoming_requests() {
        let url = request.url().to_string();
        if url.starts_with("/run?code=") {
            let code = url.trim_start_matches("/run?code=");
            let mut emu = Emulator::new();
            emu.load(code);
            let res = emu.run();
            let response = Response::from_string(res);
            let _ = request.respond(response);
        } else {
            let _ = request.respond(Response::from_string("Not Found").with_status_code(404));
        }
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
