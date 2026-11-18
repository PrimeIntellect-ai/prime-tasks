#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl openssl pkg-config libssl-dev build-essential
    pip3 install pytest cryptography

    # Install Rust
    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    chmod -R 777 /opt/rust /opt/cargo
    export PATH="/opt/cargo/bin:$PATH"

    # Create user
    useradd -m -s /bin/bash user || true

    # Create directories
    mkdir -p /home/user/compromised_data
    mkdir -p /home/user/forensics

    # 1. Create server.log
    cat << 'EOF' > /home/user/server.log
192.168.1.10 - - [10/Oct/2023:13:55:36 -0700] "GET / HTTP/1.1" 200 2326
10.0.0.5 - - [10/Oct/2023:13:55:40 -0700] "POST /upload?filename=legit.txt HTTP/1.1" 200 102
10.0.0.5 - - [10/Oct/2023:13:56:01 -0700] "POST /upload?filename=../../compromised_data/c2_cert.pem HTTP/1.1" 200 1024
10.0.0.5 - - [10/Oct/2023:13:56:05 -0700] "POST /upload?filename=../../compromised_data/payload.enc HTTP/1.1" 200 512
EOF

    # 2. Generate CA and Certificate
    openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 \
      -subj "/C=US/ST=State/L=City/O=CompromisedCA/CN=CompromisedRoot" \
      -keyout /home/user/rootCA.key -out /home/user/rootCA.pem

    openssl req -new -newkey rsa:2048 -nodes \
      -subj "/C=US/ST=State/L=City/O=Attacker/CN=74686973697361766572797365637265746b6579313233343536373839303132" \
      -keyout /home/user/compromised_data/c2_cert.key -out /home/user/compromised_data/c2_cert.csr

    openssl x509 -req -in /home/user/compromised_data/c2_cert.csr \
      -CA /home/user/rootCA.pem -CAkey /home/user/rootCA.key -CAcreateserial \
      -out /home/user/compromised_data/c2_cert.pem -days 365 -sha256

    rm /home/user/compromised_data/c2_cert.key /home/user/compromised_data/c2_cert.csr /home/user/rootCA.key

    # 3. Encrypt the payload using Python
    cat << 'EOF' > /tmp/encrypt_payload.py
import os
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

key = bytes.fromhex("74686973697361766572797365637265746b6579313233343536373839303132")
aesgcm = AESGCM(key)
nonce = os.urandom(12)
data = b"FLAG{P4th_Tr4v3rs4l_C3rt_GCM_M4st3r}"
ct = aesgcm.encrypt(nonce, data, None)

with open("/home/user/compromised_data/payload.enc", "wb") as f:
    f.write(nonce + ct)
EOF

    python3 /tmp/encrypt_payload.py
    rm /tmp/encrypt_payload.py

    # Final permissions
    chown -R user:user /home/user/compromised_data /home/user/forensics /home/user/server.log /home/user/rootCA.pem
    chmod -R 777 /home/user
