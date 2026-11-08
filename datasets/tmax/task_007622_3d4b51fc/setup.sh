#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/traffic.txt
[08:12:44] TCP 192.168.1.100:44342 -> 192.168.1.200:80
[Suspicious Payload]
QKfAlHxfQCmb1PmbkH+f9sB5m5B8n7zAkHzAcN/U1NTUfJ+QkNDQ0N/cwNBwn/mfcN/AeZ+bcN/U1NTQ0NDf3MDQcJ/5n3Df2fmf1HXAecB9m5B8m9TcwNR/
EOF

    cat << 'EOF' > /home/user/encryptor.rs
use std::env;
use std::io::{self, Read, Write};

fn main() {
    let key: u8 = 42; // Hardcoded key for local testing, attacker might change this in actual payload
    let mut buffer = Vec::new();
    io::stdin().read_to_end(&mut buffer).unwrap();

    let mut encrypted = Vec::new();
    for &byte in buffer.iter() {
        // Linear transformation followed by XOR
        let c = (byte.wrapping_mul(5).wrapping_add(17)) ^ key;
        encrypted.push(c);
    }
    io::stdout().write_all(&encrypted).unwrap();
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
