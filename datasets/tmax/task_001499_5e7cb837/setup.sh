#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential ffmpeg
    pip3 install pytest

    # Install Rust for the agent
    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    chmod -R 777 /opt/rust
    export PATH=/opt/rust/bin:$PATH

    mkdir -p /app
    cd /app

    # Generate calibration video
    ffmpeg -f lavfi -i color=c=black:s=64x64:r=10 -t 10 -y temp_black.mp4
    ffmpeg -f lavfi -i color=c=red:s=64x64:r=10 -vframes 6 -y temp_red.mp4
    ffmpeg -f lavfi -i color=c=green:s=64x64:r=10 -vframes 4 -y temp_green.mp4

    cat << 'EOF' > inputs.txt
file 'temp_black.mp4'
inpoint 0
outpoint 2
file 'temp_red.mp4'
file 'temp_black.mp4'
inpoint 2
outpoint 5
file 'temp_green.mp4'
file 'temp_black.mp4'
inpoint 5
outpoint 8
EOF

    ffmpeg -f concat -safe 0 -i inputs.txt -c copy -y /app/calibration.mp4
    rm temp_black.mp4 temp_red.mp4 temp_green.mp4 inputs.txt

    # Create oracle anonymizer
    cat << 'EOF' > /app/oracle_anonymizer
#!/usr/bin/env python3
import sys
import json
from datetime import datetime, timedelta, timezone

def process():
    for line in sys.stdin:
        if not line.strip():
            continue
        data = json.loads(line)

        ts_str = data.get("timestamp")
        if ts_str:
            if ts_str.endswith("Z"):
                ts_str = ts_str[:-1] + "+00:00"
            dt = datetime.fromisoformat(ts_str)
            dt += timedelta(hours=6)
            data["timestamp"] = dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

        if "user_name" in data:
            data["user_name"] = "████"

        sys.stdout.write(json.dumps(data, ensure_ascii=False, separators=(',', ':')) + '\n')

if __name__ == "__main__":
    process()
EOF

    chmod +x /app/oracle_anonymizer

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
