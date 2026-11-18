#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc cargo
pip3 install pytest

mkdir -p /home/user/legacy_system
mkdir -p /home/user/web_server/src
mkdir -p /home/user/bin
mkdir -p /home/user/audit_logger/src

# 1. Binary Analysis setup
cat << 'EOF' > /home/user/legacy_system/auth_bin.c
#include <stdio.h>
int main() {
    const char* secret_hash = "HASH:81dc9bdb52d04dc20036dbd8313ed055"; // MD5 of "1234"
    printf("Auth binary loaded.\n");
    return 0;
}
EOF
gcc /home/user/legacy_system/auth_bin.c -o /home/user/legacy_system/auth_bin
rm /home/user/legacy_system/auth_bin.c

# 2. Web server setup
cat << 'EOF' > /home/user/web_server/src/main.rs
use std::collections::HashMap;

fn handle_login(query_params: HashMap<&str, &str>) -> String {
    let default_redirect = "/home";
    // Vulnerable open redirect
    let target = query_params.get("next_url").unwrap_or(&default_redirect);
    format!("HTTP/1.1 302 Found\r\nLocation: {}\r\n\r\n", target)
}

fn main() {
    println!("Web server starting...");
}
EOF

# 3. Privilege escalation setup
touch /home/user/bin/clean_logs
touch /home/user/bin/update_db
touch /home/user/bin/backup_tool
chmod +x /home/user/bin/*

# 4. Audit logger skeleton setup
cat << 'EOF' > /home/user/audit_logger/Cargo.toml
[package]
name = "audit_logger"
version = "0.1.0"
edition = "2021"

[dependencies]
aes-gcm = "0.10.3"
EOF

cat << 'EOF' > /home/user/audit_logger/src/main.rs
use aes_gcm::{
    aead::{Aead, KeyInit},
    Aes128Gcm, Nonce, Key
};
use std::fs::File;
use std::io::Write;

fn main() {
    // DO NOT CHANGE KEY OR NONCE
    let key = Key::<Aes128Gcm>::from_slice(b"secret_key_16_by"); // 16 bytes
    let nonce = Nonce::from_slice(b"unique_nonce"); // 12 bytes

    // TODO: Construct the plaintext finding string
    // let plaintext = b"PIN: ...";

    // TODO: Encrypt the plaintext using AES-128-GCM
    // TODO: Write the ciphertext to /home/user/audit_report.bin
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
# Set SUID bit after chmod -R 777 to prevent it from being cleared
chmod u+s /home/user/bin/backup_tool
