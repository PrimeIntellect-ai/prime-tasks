#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/key_service/src
    mkdir -p /home/user/mock_ssh
    mkdir -p /home/user/evidence

    VALID_KEY_1="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCv1 valid1@server"
    VALID_KEY_2="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCv2 valid2@server"
    MALICIOUS_KEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQMalici0us hacker@evil"

    echo -n "$VALID_KEY_1" | sha256sum | awk '{print $1}' > /home/user/evidence/valid_hashes.txt
    echo -n "$VALID_KEY_2" | sha256sum | awk '{print $1}' >> /home/user/evidence/valid_hashes.txt

    echo "$VALID_KEY_1" > /home/user/mock_ssh/authorized_keys
    echo "$MALICIOUS_KEY" >> /home/user/mock_ssh/authorized_keys
    echo "$VALID_KEY_2" >> /home/user/mock_ssh/authorized_keys

    chmod 777 /home/user/mock_ssh/authorized_keys
    chmod 777 /home/user/mock_ssh

    JSON_PAYLOAD="{\"action\": \"add_key\", \"key\": \"$MALICIOUS_KEY\"}"
    echo -n "$JSON_PAYLOAD" | base64 > /home/user/evidence/payload.b64

    cat << 'EOF' > /home/user/key_service/Cargo.toml
[package]
name = "key_service"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/key_service/src/main.rs
use std::fs::File;
use std::io::Write;
use std::os::unix::fs::PermissionsExt;

fn main() {
    let key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ... example@server";
    add_key(key);
}

fn add_key(key: &str) {
    let mut file = File::create("/home/user/mock_ssh/authorized_keys").unwrap();
    let mut perms = file.metadata().unwrap().permissions();
    // Vulnerability: Insecure permissions
    perms.set_mode(0o777);
    file.set_permissions(perms).unwrap();
    writeln!(file, "{}", key).unwrap();
}
EOF

    chmod -R 777 /home/user
