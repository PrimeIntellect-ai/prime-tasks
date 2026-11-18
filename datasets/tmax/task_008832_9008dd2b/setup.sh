#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl jq rustc cargo
    pip3 install pytest

    mkdir -p /home/user/session-api/src

    cat << 'EOF' > /home/user/session-api/Cargo.toml
[package]
name = "session-api"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/session-api/src/main.rs
use std::io::{Read, Write};
use std::net::TcpListener;
use std::thread;

fn process_token(token: &String) -> Result<String, String> {
    // Hidden bug: 3 uppercase letters followed by a digit
    let mut upper_count = 0;
    for c in token.chars() {
        if c.is_ascii_uppercase() {
            upper_count += 1;
        } else if c.is_ascii_digit() && upper_count == 3 {
            panic!("Intentional crash for testing!");
        } else {
            upper_count = 0;
        }
    }
    Ok(format!("Token {} is valid", token))
}

fn handle_client(mut stream: std::net::TcpStream) {
    let mut buffer = [0; 1024];
    if let Ok(bytes_read) = stream.read(&mut buffer) {
        if bytes_read == 0 { return; }
        let request = String::from_utf8_lossy(&buffer[..bytes_read]);

        // Very basic JSON extraction for the simulation
        if let Some(start) = request.find("\"token\": \"") {
            let token_start = start + 10;
            if let Some(end) = request[token_start..].find("\"") {
                let token = request[token_start..token_start+end].to_string();

                // BORROW CHECKER ERROR HERE (deliberately broken for the agent)
                // Let's create an artificial ownership error:
                let token_ref = token; // moves token

                // FIX: agent needs to change token_ref to &token or clone, but wait, the setup must contain the ERROR.
                // We will leave the error.
                let result = process_token(token_ref); // requires &String, but token_ref is String

                let response = match result {
                    Ok(_) => "HTTP/1.1 200 OK\r\n\r\nSuccess",
                    Err(_) => "HTTP/1.1 400 Bad Request\r\n\r\nInvalid",
                };
                let _ = stream.write_all(response.as_bytes());
                return;
            }
        }
        let _ = stream.write_all(b"HTTP/1.1 400 Bad Request\r\n\r\n");
    }
}

fn main() {
    let listener = TcpListener::bind("127.0.0.1:8080").unwrap();
    for stream in listener.incoming() {
        match stream {
            Ok(stream) => {
                thread::spawn(move || {
                    handle_client(stream);
                });
            }
            Err(_) => {}
        }
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
