#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /app
    cat << 'EOF' > /app/unpack.c
#include <stdlib.h>
#include <stdio.h>
int main(int argc, char **argv) {
    if (argc < 2) return 1;
    char cmd[512];
    snprintf(cmd, sizeof(cmd), "base64 -d %s", argv[1]);
    return system(cmd);
}
EOF
    gcc -O2 -s -o /app/pck_unpack /app/unpack.c
    rm /app/unpack.c

    cat << 'EOF' > /tmp/generate_data.py
import os
import json
import hashlib
import random
import base64
from datetime import datetime, timedelta

os.makedirs('/home/user/legacy_backups', exist_ok=True)

payloads = [f"User {x} performed action {x%10} in module {x%50} with result code {x%5}. Filler: " + "X"*(x%20 + 20) for x in range(1000)]
severities = ['INFO', 'WARN', 'ERROR']

start_date = datetime(2023, 1, 1)

for i in range(50):
    lines = []
    for j in range(10000):
        timestamp = (start_date + timedelta(minutes=i*10000+j)).isoformat()
        severity = random.choice(severities)
        payload = random.choice(payloads)

        md5 = hashlib.md5(payload.encode()).hexdigest()

        corrupt = random.random() < 0.05
        if corrupt:
            if random.random() < 0.5:
                payload = payload + " corrupted"
            else:
                md5 = "00000000000000000000000000000000"

        line = json.dumps({
            "timestamp": timestamp,
            "severity": severity,
            "payload": payload,
            "checksum": md5
        })
        lines.append(line)

    content = "\n".join(lines) + "\n"
    encoded = base64.b64encode(content.encode()).decode()

    with open(f'/home/user/legacy_backups/backup_{i:02d}.pck', 'w') as f:
        f.write(encoded)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
