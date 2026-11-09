#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /home/user/log_parser/src

    cat << 'EOF' > /home/user/log_parser/Cargo.toml
[package]
name = "log_parser"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/log_parser/src/main.rs
use std::fs::File;
use std::io::{self, BufRead};

fn extract_payload(line: &str) -> Option<&str> {
    // BUG 1: Off by one error (includes '<')
    let start_idx = line.find("Message: <")? + 9; 

    // BUG 2: find() stops at the first '>', failing on payloads containing '>'
    let end_idx = line.find('>')?; 

    if start_idx < end_idx {
        Some(&line[start_idx..end_idx])
    } else {
        None
    }
}

fn main() {
    let file = File::open("/home/user/server.log").expect("Could not open log file");
    let reader = io::BufReader::new(file);

    for line in reader.lines() {
        if let Ok(l) = line {
            if let Some(payload) = extract_payload(&l) {
                println!("{}", payload);
            }
        }
    }
}
EOF

    cat << 'EOF' > /home/user/server.log
[08:00:01] (INFO) - Message: <Service started cleanly>
[08:00:05] (WARN) - Message: <Missing fallback configuration>
[08:00:10] (ERROR) - Message: <Failed to parse payload: <xml><error>Unclosed tag</error></xml>>
[08:00:15] (INFO) - Message: <Request complete: status -> success>
[08:00:20] (INFO) - Message: <Shutdown sequence initiated>
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
