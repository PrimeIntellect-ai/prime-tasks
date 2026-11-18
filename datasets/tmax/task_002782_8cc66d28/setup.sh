#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ sqlite3 libsqlite3-dev espeak ffmpeg
    pip3 install pytest SpeechRecognition pydub

    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Generate voicemail
    espeak -w /app/voicemail.wav "Hi, it's Alice. The new telemetry data schema is confusing. Don't use the 'src' and 'dst' columns. The true origin node is in the 'tx_endpoint' column, and the destination is 'rx_endpoint'. To detect a malicious batch, you need to calculate the rolling sum of the 'bytes' column for each 'tx_endpoint', ordered by 'timestamp'. If the rolling sum of the current and previous 2 rows for any given node exceeds 15000 bytes, or if the batch introduces a routing cycle in the graph, it's an anomaly and must be dropped. Also, if you use SQLite, be sure to create a composite index on tx_endpoint and timestamp to speed up the window function."

    # Generate CSV files
    cat << 'EOF' > /tmp/gen_data.py
import csv
import random
import os

def write_csv(path, rows):
    with open(path, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['id','src','dst','tx_endpoint','rx_endpoint','bytes','timestamp'])
        for r in rows:
            writer.writerow(r)

# Clean: acyclic, rolling sum <= 15000
for i in range(50):
    rows = []
    # Acyclic graph: A->B, B->C, etc.
    nodes = [f"N{j}" for j in range(10)]
    ts = 1000
    for j in range(8):
        tx = nodes[j]
        rx = nodes[j+1]
        b = random.randint(100, 4000)
        rows.append([j, "s", "d", tx, rx, b, ts + j])
    write_csv(f"/app/corpora/clean/clean_{i}.csv", rows)

# Evil: 25 cycle, 25 rolling sum > 15000
for i in range(25):
    # Cycle
    rows = []
    ts = 1000
    tx_rx = [("A","B"), ("B","C"), ("C","A")]
    for j, (tx, rx) in enumerate(tx_rx):
        rows.append([j, "s", "d", tx, rx, 1000, ts + j])
    write_csv(f"/app/corpora/evil/evil_cycle_{i}.csv", rows)

for i in range(25, 50):
    # Rolling sum > 15000
    rows = []
    ts = 1000
    tx = "A"
    for j in range(3):
        rx = f"B{j}"
        rows.append([j, "s", "d", tx, rx, 6000, ts + j])
    write_csv(f"/app/corpora/evil/evil_sum_{i}.csv", rows)

EOF
    python3 /tmp/gen_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
