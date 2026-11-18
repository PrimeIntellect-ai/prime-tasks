#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    cat << 'EOF' > /tmp/setup.py
import os

os.makedirs("/app/corpus/clean", exist_ok=True)
os.makedirs("/app/corpus/evil", exist_ok=True)

# Generate clean
for i in range(10):
    with open(f"/app/corpus/clean/clean_{i}.csv", "w") as f:
        f.write("timestamp,sensor_id,value,status\n")
        for j in range(5):
            f.write(f"2023-01-01T00:0{j}:00Z,{i},{j*2.5},OK\n")

# Generate evil
for i in range(10):
    with open(f"/app/corpus/evil/evil_{i}.csv", "w") as f:
        f.write("timestamp,sensor_id,value,status\n")
        if i % 3 == 0:
            f.write(f"2023-01-01T00:00:00Z,{i},{i*2.5}\n") # missing column
        elif i % 3 == 1:
            f.write(f"2023-01-01T00:00:00Z,{i},{i*2.5},OK,EXTRA\n") # extra column
        else:
            f.write(f"2023-01-01T00:00:00Z,{i},\"10.0\n20.0\",OK\n") # embedded newline

# Generate audio
with open("/app/audio_rule.wav", "wb") as f:
    f.write(b"RIFF\x00\x00\x00\x00WAVEfmt \x10\x00\x00\x00\x01\x00\x01\x00\x44\xac\x00\x00\x88\x58\x01\x00\x02\x00\x10\x00data\x00\x00\x00\x00")
    f.write(b"Group data by the hour of the timestamp. Extract the first 2 rows per hour.\n")
EOF

    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
