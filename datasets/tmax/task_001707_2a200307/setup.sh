#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    # Install Rust
    export RUSTUP_HOME=/opt/rust/rustup
    export CARGO_HOME=/opt/rust/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/opt/rust/cargo/bin:$PATH"
    ln -s /opt/rust/cargo/bin/* /usr/local/bin/

    # Create user
    useradd -m -s /bin/bash user || true

    # Create data directory and file using Python to avoid bash escaping issues
    python3 -c '
import os
os.makedirs("/home/user/data", exist_ok=True)
with open("/home/user/data/raw_metrics.jsonl", "w") as f:
    f.write("{\"id\": \"sensor_A\", \"timestamp\": 2, \"measurement\": 20.0}\n")
    f.write("{\"id\": \"sensor_\\uFF21\", \"timestamp\": 1, \"measurement\": 10.0}\n")
    f.write("{\"id\": \"sensor_A\", \"timestamp\": 4, \"measurement\": 40.0}\n")
    f.write("{\"id\": \"sensor_\\u0041\", \"timestamp\": 3, \"measurement\": 30.0}\n")
    f.write("{\"id\": \"sensor_\\u212B\", \"timestamp\": 10, \"measurement\": 5.0}\n")
    f.write("{\"id\": \"sensor_\\u00C5\", \"timestamp\": 11, \"measurement\": 15.0}\n")
    f.write("{\"id\": \"sensor_\\u0041\\u030A\", \"timestamp\": 12, \"measurement\": 10.0}\n")
'

    chown -R user:user /home/user/data
    chmod -R 777 /home/user
