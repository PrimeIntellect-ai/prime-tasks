#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl ffmpeg sqlite3 build-essential
    pip3 install pytest

    # Install Rust globally
    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
    export PATH="/opt/rust/bin:$PATH"

    # Create directories
    mkdir -p /app/corpus/clean /app/corpus/evil /home/user

    # Generate video (fast encoding)
    ffmpeg -f lavfi -i testsrc=duration=60:size=320x240:rate=10 -c:v libx264 -preset ultrafast /app/drone_footage.mp4

    # Generate JSON corpus
    python3 -c '
import os, json
for i in range(50):
    with open(f"/app/corpus/clean/clean_{i}.json", "w") as f:
        json.dump({"metadata": {"id": i, "value": "safe"}}, f)
for i in range(25):
    with open(f"/app/corpus/evil/evil_depth_{i}.json", "w") as f:
        json.dump({"level1": {"level2": {"level3": {"level4": "too deep"}}}}, f)
for i in range(25):
    with open(f"/app/corpus/evil/evil_sql_{i}.json", "w") as f:
        json.dump({"metadata": {"id": i, "value": "DROP TABLE frames;"}}, f)
'

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /opt/rust
    chmod -R 777 /app
    chmod -R 777 /home/user
