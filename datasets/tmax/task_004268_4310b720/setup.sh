#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils openssl curl
    pip3 install pytest

    # Install Rust globally
    export RUSTUP_HOME=/usr/local/rustup
    export CARGO_HOME=/usr/local/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
    chmod -R 777 /usr/local/rustup /usr/local/cargo

    # Setup task files
    mkdir -p /home/user
    cd /home/user

    # Create a dummy C program and compile it
    echo 'int main() { return 0; }' > dummy.c
    gcc dummy.c -o dummy_bin

    # Create the policy file and add it as a custom section to the ELF
    echo -n "PORT=8443" > policy.txt
    objcopy --add-section .audit_policy=policy.txt --set-section-flags .audit_policy=noload,readonly dummy_bin app_binary

    # Clean up temporary compilation files
    rm dummy.c dummy_bin policy.txt

    # Generate the TLS certificate
    openssl req -x509 -newkey rsa:2048 -keyout /home/user/key.pem -out /home/user/cert.pem -days 365 -nodes -subj "/C=US/ST=CA/L=SF/O=Test/CN=SecureCorpApp"

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
