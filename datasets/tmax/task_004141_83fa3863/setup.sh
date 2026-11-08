#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential tar
    pip3 install pytest

    # Install Rust globally so the agent can use cargo
    export RUSTUP_HOME=/opt/rustup
    export CARGO_HOME=/opt/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
    chmod -R 777 /opt/rustup /opt/cargo
    ln -s /opt/cargo/bin/* /usr/local/bin/

    # Generate initial state
    mkdir -p /home/user/setup_tmp
    cd /home/user/setup_tmp

    cat << 'EOF' > gen.py
import struct
import os
import tarfile

def write_artifact(filename, name, payload):
    name_bytes = name.encode('utf-8')
    with open(filename, 'wb') as f:
        f.write(b'ARTF')
        f.write(b'\x01')
        f.write(struct.pack('<H', len(name_bytes)))
        f.write(name_bytes)
        f.write(struct.pack('<Q', len(payload)))
        f.write(payload)

# Artifact 1: "lib_core.so", size 2500 bytes
payload1 = bytes([i % 256 for i in range(2500)])
write_artifact("art1.bin", "lib_core.so", payload1)

# Artifact 2: "config.dat", size 1024 bytes
payload2 = bytes([(i * 2) % 256 for i in range(1024)])
write_artifact("art2.bin", "config.dat", payload2)

with tarfile.open("/home/user/artifacts.tar.gz", "w:gz") as tar:
    tar.add("art1.bin", arcname="art1.bin")
    tar.add("art2.bin", arcname="art2.bin")
EOF

    python3 gen.py
    rm -rf /home/user/setup_tmp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
