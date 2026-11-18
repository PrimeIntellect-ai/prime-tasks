#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential gcc
    pip3 install pytest

    # Install Rust
    export RUSTUP_HOME=/opt/rust/rustup
    export CARGO_HOME=/opt/rust/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    chmod -R 777 /opt/rust
    ln -s /opt/rust/cargo/bin/* /usr/local/bin/

    # Create user and home directory
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    # Generate the dummy dataset
    cat << 'EOF' > /tmp/generate_data.py
import struct
import gzip

records = [
    (b'SENS', 10, 1600000000, b'\x01\x02\x03'),
    (b'SENS', 42, 1600000050, b'\xaa\xbb\xcc\xdd'),
    (b'SENS', 99, 1600000099, b'\xff\xff'),
    (b'SENS', 42, 1600000100, b'\x11\x22\x33\x44\x55'),
    (b'SENS', 42, 1600000200, b''),
    (b'SENS', 12, 1600000250, b'\x00\x00\x00'),
]

with gzip.open('/home/user/sensor_data.raw.gz', 'wb') as f:
    for magic, sensor_id, timestamp, payload in records:
        length = len(payload)
        header = struct.pack('>4sHQH', magic, sensor_id, timestamp, length)
        f.write(header + payload)
EOF
    python3 /tmp/generate_data.py

    # Set permissions
    chmod -R 777 /home/user
