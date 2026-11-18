#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip curl build-essential cargo
pip3 install pytest

mkdir -p /home/user/project/src
mkdir -p /home/user/project/lib

cat << 'EOF' > /home/user/project/Cargo.toml
[package]
name = "api_server"
version = "0.1.0"
edition = "2021"

[dependencies]
libc = "0.2"

[build-dependencies]
cc = "1.0"
EOF

cat << 'EOF' > /home/user/project/build.rs
fn main() {
    cc::Build::new()
        .file("lib/transform.c")
        .compile("transform");
}
EOF

cat << 'EOF' > /home/user/project/lib/transform.c
#include <stdlib.h>
#include <string.h>

char* transform_string(const char* input) {
    char buffer[1024];
    strncpy(buffer, input, 1023);
    buffer[1023] = '\0';
    for(int i=0; buffer[i]; i++) {
        if(buffer[i] >= 'a' && buffer[i] <= 'z') {
            buffer[i] = buffer[i] - 32;
        }
    }
    return buffer; // memory safety bug
}

void free_string(char* ptr) {
    free(ptr);
}
EOF

cat << 'EOF' > /home/user/project/src/main.rs
use std::io::{Read, Write};
use std::net::TcpListener;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

#[link(name = "transform", kind = "static")]
extern "C" {
    fn transform_string(input: c_char) -> *mut c_char; // compilation error
    fn free_string(ptr: *mut c_char);
}

fn main() {
    let listener = TcpListener::bind("127.0.0.1:8080").unwrap();
    for stream in listener.incoming() {
        let mut stream = stream.unwrap();
        let mut buffer = [0; 1024];
        let bytes_read = stream.read(&mut buffer).unwrap_or(0);
        if bytes_read == 0 { continue; }

        if buffer.starts_with(b"GET /api/transform?text=") {
            let req = String::from_utf8_lossy(&buffer);
            let text_start = req.find("?text=").unwrap() + 6;
            let text_end = req[text_start..].find(' ').unwrap_or(req.len() - text_start) + text_start;
            let input_text = &req[text_start..text_end];

            let c_input = CString::new(input_text).unwrap();

            unsafe {
                let result_ptr = transform_string(c_input.as_ptr());
                let c_result = CStr::from_ptr(result_ptr);
                let result_str = c_result.to_str().unwrap();

                let response = format!("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: {}\r\n\r\n{}", result_str.len(), result_str);
                stream.write_all(response.as_bytes()).unwrap();

                free_string(result_ptr);
            }
        }
    }
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
