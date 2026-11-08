#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import json
import random

start_time = 1700000000

with open('/home/user/telemetry.jsonl', 'w') as f:
    for hour in range(15):
        bucket_start = start_time + (hour * 3600)

        # Determine number of edits
        if hour == 8:
            edits = 45 # Anomaly! (Baseline avg will be ~10, 3x10=30)
        else:
            edits = 10

        for i in range(edits):
            ts = bucket_start + random.randint(0, 3599)
            f.write('{"timestamp": ' + str(ts) + ', "action": "edit", "user": "loc_1", "status": "success", "text": "test"}\n')

        # Add some failed/malformed lines
        for i in range(2):
            ts = bucket_start + random.randint(0, 3599)
            f.write('{"timestamp": ' + str(ts) + ', "action": "edit", "user": "loc_1", "status": "failed", "text": "bad\\uG"}\n')
EOF

    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
