#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar
    pip3 install pytest

    mkdir -p /home/user/backups
    mkdir -p /home/user/parsed/split
    mkdir -p /tmp/setup_data

    cat << 'EOF' > /tmp/setup_data/generate_logs.py
import json

logs = []
for i in range(500):
    severity = "CRITICAL" if i % 12 == 0 else ("WARNING" if i % 5 == 0 else "INFO")
    logs.append(json.dumps({"id": i, "severity": severity, "message": f"Log message {i}"}))

with open("/tmp/setup_data/full.log", "w") as f:
    f.write("\n".join(logs) + "\n")
EOF

    python3 /tmp/setup_data/generate_logs.py

    cd /tmp/setup_data
    split -l 50 full.log chunk_

    mv chunk_aa chunk_00
    mv chunk_ab chunk_01
    mv chunk_ac chunk_02
    mv chunk_ad chunk_03
    mv chunk_ae chunk_04
    mv chunk_af chunk_05
    mv chunk_ag chunk_06
    mv chunk_ah chunk_07
    mv chunk_ai chunk_08
    mv chunk_aj chunk_09

    tar -czf part_1.tar.gz chunk_00 chunk_01 chunk_02 chunk_03 chunk_04
    tar -czf part_2.tar.gz chunk_05 chunk_06 chunk_07 chunk_08 chunk_09

    tar -cf /home/user/backups/master_backup.tar part_1.tar.gz part_2.tar.gz
    rm -rf /tmp/setup_data

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
