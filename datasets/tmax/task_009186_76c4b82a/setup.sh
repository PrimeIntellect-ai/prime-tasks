#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl gcc make libc6-dev rustc cargo
    pip3 install pytest

    mkdir -p /home/user/polyglot-service/src
    mkdir -p /home/user/polyglot-service/c_src

    cat << 'EOF' > /home/user/polyglot-service/Cargo.toml
[package]
name = "polyglot-service"
version = "0.1.0"
edition = "2021"
build = "build.rs"

[dependencies]
EOF

    cat << 'EOF' > /home/user/polyglot-service/build.rs
use std::env;
use std::path::PathBuf;

fn main() {
    let dir = env::var("CARGO_MANIFEST_DIR").unwrap();
    println!("cargo:rustc-link-search=native={}/c_src", dir);
    println!("cargo:rustc-link-lib=static=api_processor");
}
EOF

    cat << 'EOF' > /home/user/polyglot-service/src/main.rs
use std::io::{Read, Write};
use std::net::TcpListener;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

extern "C" {
    fn process_request(method: *const c_char, path: *const c_char, query: *const c_char, response: *mut c_char);
}

fn main() {
    let listener = TcpListener::bind("127.0.0.1:8080").unwrap();
    for stream in listener.incoming() {
        let mut stream = stream.unwrap();
        let mut buffer = [0; 1024];
        stream.read(&mut buffer).unwrap();

        let request = String::from_utf8_lossy(&buffer);
        let first_line = request.lines().next().unwrap_or("");
        let parts: Vec<&str> = first_line.split_whitespace().collect();

        if parts.len() >= 2 {
            let method = CString::new(parts[0]).unwrap();
            let full_path = parts[1];

            let (path, query) = if let Some(idx) = full_path.find('?') {
                (&full_path[..idx], &full_path[idx+1..])
            } else {
                (full_path, "")
            };

            let c_path = CString::new(path).unwrap();
            let c_query = CString::new(query).unwrap();

            let mut response_buf = [0i8; 256];

            unsafe {
                process_request(
                    method.as_ptr(),
                    c_path.as_ptr(),
                    c_query.as_ptr(),
                    response_buf.as_mut_ptr()
                );
            }

            let response_str = unsafe { CStr::from_ptr(response_buf.as_ptr()) }.to_string_lossy();
            let http_response = format!(
                "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{}",
                response_str
            );
            stream.write(http_response.as_bytes()).unwrap();
            stream.flush().unwrap();
        }
    }
}
EOF

    cat << 'EOF' > /home/user/polyglot-service/c_src/Makefile
all: libprocessor.so

libprocessor.so: processor.c
	gcc -o libprocessor.so processor.c
EOF

    cat << 'EOF' > /home/user/polyglot-service/c_src/processor.h
#ifndef PROCESSOR_H
#define PROCESSOR_H

void process_request(char* method, char* path, char* query, char* response);

#endif
EOF

    cat << 'EOF' > /home/user/polyglot-service/c_src/processor.c
#include "processor.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

// Buggy signature and implementation
void process_request(char* method, char* path, char* query, char* response) {
    sprintf(response, "{\"error\": \"not_implemented\"}");
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/polyglot-service
    chmod -R 777 /home/user
