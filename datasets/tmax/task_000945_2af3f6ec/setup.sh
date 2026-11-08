#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git strace
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/pipeline/logs
    mkdir -p /home/user/.cache/pipeline_data

    cd /home/user/pipeline
    git config --global user.email "test@example.com"
    git config --global user.name "Test User"
    git init

    cat << 'EOF' > README.md
# Data Pipeline
EOF
    git add README.md
    git commit -m "Initial commit"

    cat << 'EOF' > settings.conf
SECRET_KEY="super_secret_build_key_77a91"
DEBUG=True
EOF
    git add settings.conf
    git commit -m "Add dev settings"

    rm settings.conf
    cat << 'EOF' > settings.conf
# Key removed for security
DEBUG=True
EOF
    git add settings.conf
    git commit -m "Remove secret key"

    # Setup Logs (Timeline Anomaly)
    echo "[2023-10-01 10:00:01] [WEB] [WEB_REQUEST] tx-1001" > logs/web.log
    echo "[2023-10-01 10:00:05] [DB] [DB_COMMIT] tx-1001" > logs/db.log

    echo "[2023-10-01 10:05:10] [WEB] [WEB_REQUEST] tx-9942-err" >> logs/web.log
    echo "[2023-10-01 10:05:08] [DB] [DB_COMMIT] tx-9942-err" >> logs/db.log

    echo "[2023-10-01 10:10:00] [WEB] [WEB_REQUEST] tx-1002" >> logs/web.log
    echo "[2023-10-01 10:10:02] [DB] [DB_COMMIT] tx-1002" >> logs/db.log

    # Create the hidden config
    echo "broken_json_content" > /home/user/.cache/pipeline_data/fallback_config.json

    # Create the python script
    cat << 'EOF' > build.py
import os
import sys
import json
from datetime import datetime

# Obfuscated config read to force strace usage
def load_config():
    config_path = bytes.fromhex('2f686f6d652f757365722f2e63616368652f706970656c696e655f646174612f66616c6c6261636b5f636f6e6669672e6a736f6e').decode('utf-8')
    try:
        with open(config_path, 'r') as f:
            return json.load(f)
    except Exception as e:
        print(f"Failed to load config. System error.")
        sys.exit(1)

def main():
    config = load_config()

    secret = os.environ.get("SECRET_KEY")
    if secret != "super_secret_build_key_77a91":
        print("Missing or invalid SECRET_KEY environment variable.")
        sys.exit(1)

    # Read logs
    events = []
    with open("logs/web.log", "r") as f:
        for line in f:
            parts = line.strip().split("] [")
            ts = parts[0][1:]
            tx_id = parts[2].split("] ")[1]
            events.append((datetime.strptime(ts, "%Y-%m-%d %H:%M:%S"), "WEB", tx_id))

    with open("logs/db.log", "r") as f:
        for line in f:
            parts = line.strip().split("] [")
            ts = parts[0][1:]
            tx_id = parts[2].split("] ")[1]
            events.append((datetime.strptime(ts, "%Y-%m-%d %H:%M:%S"), "DB", tx_id))

    events.sort(key=lambda x: x[0])

    tx_state = {}
    for ts, source, tx_id in events:
        if tx_id not in tx_state:
            tx_state[tx_id] = []
        tx_state[tx_id].append(source)

        if tx_state[tx_id] == ["DB"]:
            raise ValueError(f"Timeline anomaly: DB_COMMIT before WEB_REQUEST for transaction {tx_id}")

    print("Build successful.")

if __name__ == "__main__":
    main()
EOF

    chmod +x build.py

    chown -R user:user /home/user
    chmod -R 777 /home/user
