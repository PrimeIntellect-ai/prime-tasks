#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential sudo espeak
    pip3 install pytest

    # Install rustup and cargo globally
    export RUSTUP_HOME=/usr/local/rustup
    export CARGO_HOME=/usr/local/cargo
    export PATH=/usr/local/cargo/bin:$PATH
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
    chmod -R 777 /usr/local/rustup /usr/local/cargo

    # Create the audio file
    mkdir -p /app
    espeak -w /app/voicemail.wav "The secret code is delta tango seven."
    chmod 777 /app/voicemail.wav

    # Create user and give sudo privileges
    useradd -m -s /bin/bash user || true
    echo "user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

    # Create the starter codebase
    mkdir -p /home/user/audio-server/src
    cat << 'EOF' > /home/user/audio-server/Cargo.toml
[package]
name = "audio-server"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/audio-server/src/main.rs
fn main() {
    // TODO: Implement HTTP server and audio analysis
    println!("Broken server...");
}
EOF

    chmod -R 777 /home/user
