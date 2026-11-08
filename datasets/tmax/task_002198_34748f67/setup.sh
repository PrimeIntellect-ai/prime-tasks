#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup_logs.py
import json
import random

random.seed(42)

logs = []
for i in range(300):
    base_time = random.uniform(40.0, 60.0)

    # Normal message
    msg = "User action processed successfully."

    if i == 142:
        # Inject anomaly
        base_time = 300.0
        # Japanese message: "データベースの接続に失敗しました: タイムアウト" (Failed to connect to database: timeout)
        msg = "データベースの接続に失敗しました: タイムアウト"

    log = {
        "timestamp": f"2023-10-01T12:{i//60:02d}:{i%60:02d}Z",
        "message": msg,
        "processing_time_ms": base_time
    }
    logs.append(log)

with open('/home/user/app_logs.jsonl', 'w', encoding='utf-8') as f:
    for log in logs:
        f.write(json.dumps(log, ensure_ascii=False) + '\n')
EOF

    python3 /home/user/setup_logs.py
    rm /home/user/setup_logs.py

    chmod -R 777 /home/user
