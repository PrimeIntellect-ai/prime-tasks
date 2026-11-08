#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential rustc cargo
    pip3 install pytest

    mkdir -p /home/user/ws_grpc_proxy/c_ext
    mkdir -p /home/user/ws_grpc_proxy/proto
    mkdir -p /home/user/ws_grpc_proxy/src

    cat << 'EOF' > /home/user/ws_grpc_proxy/c_ext/validator.c
#include <string.h>

void validate_token(const char* input) {
    char buf[32];
    strcpy(buf, input);
}
EOF

    cat << 'EOF' > /home/user/ws_grpc_proxy/proto/service.proto
syntax = "proto2";

message ProxyRequest {
    string payload = 1;
}
EOF

    cat << 'EOF' > /home/user/ws_grpc_proxy/Cargo.toml
[package]
name = "ws_grpc_proxy"
version = "0.1.0"
edition = "2021"

[dependencies]
tokio = { version = "1.0", features = ["full"] }

[build-dependencies]
cc = "1.0"
EOF

    cat << 'EOF' > /home/user/ws_grpc_proxy/build.rs
fn main() {
    cc::Build::new()
        .file("c_ext/validator.c")
        .flag("-Werror=stringop-overflow")
        .compile("validator");
}
EOF

    cat << 'EOF' > /home/user/ws_grpc_proxy/src/main.rs
use std::net::TcpListener;
use std::io::{Read, Write};

extern "C" {
    fn validate_token(input: *const std::ffi::c_char);
}

fn main() {
    let listener = TcpListener::bind("127.0.0.1:8080").unwrap();
    for stream in listener.incoming() {
        let mut stream = stream.unwrap();
        let mut buf = [0; 1024];
        stream.read(&mut buf).unwrap();

        let response = "HTTP/1.1 101 Switching Protocols\r\n\
                        Upgrade: websocket\r\n\
                        Connection: Upgrade\r\n\
                        Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n\r\n";
        stream.write(response.as_bytes()).unwrap();
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
