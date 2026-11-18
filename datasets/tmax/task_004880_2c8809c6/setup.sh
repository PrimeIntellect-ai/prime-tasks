#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate audio file
    espeak -w /app/urgent_alert.wav "Please route this immediately to the oncall network team."

    # Generate clean and evil corpus
    python3 -c '
import os
for i in range(50):
    with open(f"/app/corpus/clean/alert_{i}.txt", "w") as f:
        f.write(f"[ALERT] CPU usage at {i+50}%\n[WARNING] Disk space low on /dev/sda1\n")
for i in range(50):
    with open(f"/app/corpus/evil/spam_{i}.txt", "w") as f:
        f.write(f"Click here to claim your prize http://example.com/prize{i}\nCrypto investment opportunity!\n")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
