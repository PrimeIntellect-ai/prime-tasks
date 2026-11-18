#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl espeak sqlite3
    pip3 install pytest

    # Install Rust for the agent
    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/opt/rust/bin:$PATH"
    chmod -R 777 /opt/rust

    mkdir -p /app

    # Generate audio file
    espeak -w /app/schema_rules.wav "All valid records must have a device ID starting exactly with the uppercase prefix DEV hyphen. Also, the temperature reading must be strictly less than one hundred point zero."

    # Create raw data
    cat << 'EOF' > /app/raw_data.jsonl
{"device_id": "DEV-123", "temperature": 45.0, "notes": "test"}
{"device_id": "ABC-123", "temperature": 45.0, "notes": "test"}
{"device_id": "DEV-124", "temperature": 105.0, "notes": "test"}
EOF

    # Create oracle cleaner (as a Python script disguised as a binary for simplicity)
    cat << 'EOF' > /app/oracle_cleaner
#!/usr/bin/env python3
import sys
import json
import re

def process_line(line):
    # A simplified version of the oracle logic
    try:
        data = json.loads(line)
        if data.get("device_id", "").startswith("DEV-") and data.get("temperature", 1000) < 100.0:
            # Handle basic unicode replacement if needed, though json.loads handles valid ones
            print(json.dumps(data, separators=(',', ':')))
    except:
        pass

for line in sys.stdin:
    process_line(line)
EOF
    chmod +x /app/oracle_cleaner

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
