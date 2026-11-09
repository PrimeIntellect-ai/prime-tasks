#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential cargo rustc
    pip3 install pytest

    mkdir -p /home/user/project/c_ext
    mkdir -p /home/user/project/src

    cat << 'EOF' > /home/user/project/c_ext/parser.c
#include <string.h>
#include <stdio.h>

void process_string(const char* input, char* output) {
    // BUG: Unbounded strcpy into a 16-byte buffer
    strcpy(output, input);
}
EOF

    cat << 'EOF' > /home/user/project/c_ext/parser.h
void process_string(const char* input, char* output);
EOF

    cat << 'EOF' > /home/user/project/build.rs
fn main() {
    // TODO: Use cc crate to compile c_ext/parser.c and link it
}
EOF

    cat << 'EOF' > /home/user/project/Cargo.toml
[package]
name = "rust_processor"
version = "0.1.0"
edition = "2021"

[build-dependencies]
cc = "1.0"
EOF

    cat << 'EOF' > /home/user/project/src/main.rs
use std::env;
use std::ffi::CString;
use std::os::raw::c_char;

extern "C" {
    fn process_string(input: *const c_char, output: *mut c_char);
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        return;
    }

    let input = CString::new(args[1].clone()).unwrap();
    let mut output = vec![0u8; 16];

    unsafe {
        process_string(input.as_ptr(), output.as_mut_ptr() as *mut c_char);
    }

    let result = CString::from_vec_with_nul(output).unwrap();
    println!("{}", result.into_string().unwrap());
}
EOF

    cat << 'EOF' > /home/user/project/gateway.py
import json
import subprocess
from http.server import BaseHTTPRequestHandler, HTTPServer

class RequestHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length)

        # TODO: Implement validation and rate limiting

        req = json.loads(post_data)
        data = req.get("data", "")

        result = subprocess.run(
            ["./target/debug/rust_processor", data],
            capture_output=True, text=True
        )

        self.send_response(200)
        self.end_headers()
        self.wfile.write(result.stdout.encode())

if __name__ == "__main__":
    server = HTTPServer(('0.0.0.0', 8080), RequestHandler)
    server.serve_forever()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
