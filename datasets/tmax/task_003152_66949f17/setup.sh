#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl espeak ffmpeg build-essential
    pip3 install pytest

    # Install PyTorch CPU and Whisper to avoid timeout
    pip3 install torch --index-url https://download.pytorch.org/whl/cpu
    pip3 install openai-whisper

    # Install Rust globally
    export RUSTUP_HOME=/opt/rust/rustup
    export CARGO_HOME=/opt/rust/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    chmod -R 777 /opt/rust

    # Create the audio file
    mkdir -p /app
    espeak -w /app/dictation.wav "Alanine, Cysteine, Aspartic Acid, Phenylalanine, Glycine."

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
