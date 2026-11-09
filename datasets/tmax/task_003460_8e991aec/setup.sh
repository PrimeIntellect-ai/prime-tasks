#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    # Install Rust globally so the agent can use it
    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    chmod -R 777 /opt/rust /opt/cargo
    export PATH=/opt/cargo/bin:$PATH

    mkdir -p /home/user

    # Create the setup script for generating the input file
    cat << 'EOF' > /tmp/setup.py
import json
import os

events = [
    # Safe events
    {"timestamp": 1000000000000, "service": "Auth-US", "change_id": "c1", "payload_size": 100},
    {"timestamp": 1000000005000, "service": "Auth-US", "change_id": "c2", "payload_size": 100},

    # Violation in Auth-US (900ms difference)
    {"timestamp": 1000000005900, "service": "Auth-US", "change_id": "c3", "payload_size": 100},

    # Safe event in Unicode service
    {"timestamp": 1000000000000, "service": "ユーザー管理", "change_id": "c4", "payload_size": 100},

    # Violation in Unicode service (500ms difference)
    {"timestamp": 1000000000500, "service": "ユーザー管理", "change_id": "c5", "payload_size": 100},

    # Another safe event in Unicode service
    {"timestamp": 1000000002000, "service": "ユーザー管理", "change_id": "c6", "payload_size": 100},

    # Chained violation (800ms difference from c6)
    {"timestamp": 1000000002800, "service": "ユーザー管理", "change_id": "c7", "payload_size": 100},

    # Out of order in file, but should be sorted by agent
    {"timestamp": 999999999000, "service": "Auth-US", "change_id": "c0", "payload_size": 100},

    # Exact 1000ms difference (Should NOT be a violation)
    {"timestamp": 1000000003800, "service": "ユーザー管理", "change_id": "c8", "payload_size": 100},
]

os.makedirs("/home/user", exist_ok=True)
with open("/home/user/config_events.jsonl", "w", encoding="utf-8") as f:
    for event in events:
        f.write(json.dumps(event, ensure_ascii=False) + "\n")
EOF

    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
