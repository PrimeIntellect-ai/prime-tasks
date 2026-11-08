#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg cargo rustc build-essential
    pip3 install pytest

    mkdir -p /app/corpus/incoming
    mkdir -p /app/verifier_corpus/evil
    mkdir -p /app/verifier_corpus/clean

    # Create dummy video with subtitle track
    cat << 'EOF' > /tmp/sub.srt
1
00:00:00,000 --> 00:00:02,000
PAYLOAD_SIG: 0xDE 0xAD 0xBE 0xEF 0x42 0x13 0x37
EOF
    ffmpeg -f lavfi -i color=c=black:s=320x240:d=2 -i /tmp/sub.srt -c:v libx264 -c:s mov_text -map 0:v -map 1:s /app/incident_record.mp4

    # Generate files
    python3 -c "
import os, random
sig = b'\xDE\xAD\xBE\xEF\x42\x13\x37'

def make_file(path, evil):
    size = random.randint(100, 500)
    data = bytearray(os.urandom(size))
    if evil:
        idx = random.randint(0, size - len(sig))
        data[idx:idx+len(sig)] = sig
    with open(path, 'wb') as f:
        f.write(data)

for i in range(20):
    make_file(f'/app/corpus/incoming/file_{i}.bin', evil=(i%2==0))

for i in range(50):
    make_file(f'/app/verifier_corpus/evil/file_{i}.bin', evil=True)

for i in range(50):
    make_file(f'/app/verifier_corpus/clean/file_{i}.bin', evil=False)
"

    # Pre-fetch memmap2 crate
    export CARGO_HOME=/usr/local/cargo
    export RUSTUP_HOME=/usr/local/rustup
    mkdir -p /tmp/dummy_proj
    cd /tmp/dummy_proj
    cargo init --bin
    cargo add memmap2
    cargo build
    cd /
    rm -rf /tmp/dummy_proj
    chmod -R 777 $CARGO_HOME

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
