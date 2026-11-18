#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        cmake \
        build-essential \
        curl \
        wget \
        netcat-openbsd \
        pv

    pip3 install pytest numpy

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="$HOME/.cargo/bin:$PATH"

    # Install websocat manually
    wget -O /usr/local/bin/websocat https://github.com/vi/websocat/releases/download/v1.11.0/websocat.x86_64-unknown-linux-musl
    chmod +x /usr/local/bin/websocat

    # Create directories
    mkdir -p /home/user/AudioStreamer/c_filter
    mkdir -p /home/user/AudioStreamer/rust_server/src
    mkdir -p /app

    # Create files for initial state tests
    touch /home/user/AudioStreamer/c_filter/CMakeLists.txt
    touch /home/user/AudioStreamer/rust_server/Cargo.toml
    touch /home/user/AudioStreamer/rust_server/src/main.rs
    touch /home/user/AudioStreamer/client_chunker.py

    # Generate dummy wav files
    python3 -c "import wave, struct; f=wave.open('/app/test_audio.wav', 'w'); f.setnchannels(1); f.setsampwidth(2); f.setframerate(44100); f.writeframes(struct.pack('<h', 0)*44100); f.close()"
    python3 -c "import wave, struct; f=wave.open('/app/golden_processed.wav', 'w'); f.setnchannels(1); f.setsampwidth(2); f.setframerate(44100); f.writeframes(struct.pack('<h', 0)*44100); f.close()"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
