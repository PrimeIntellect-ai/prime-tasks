#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make espeak
    pip3 install pytest

    mkdir -p /app/verifier/corpus/clean
    mkdir -p /app/verifier/corpus/evil

    # Generate audio file
    espeak -w /app/incident_dictation.wav "We need to fix the log parser. It must properly handle CSVs with embedded newlines. Flag any log file where a message has a UTF-8 character Levenshtein distance of two or less to the word 'firewall'. Also, aggregate the timestamps into ten minute buckets based on the epoch time. If any ten minute bucket contains more than fifty events, flag the file as well."

    # Generate corpus files
    cat << 'EOF' > /tmp/gen_corpus.py
import os
import csv
from datetime import datetime, timedelta

clean_dir = "/app/verifier/corpus/clean"
evil_dir = "/app/verifier/corpus/evil"

def write_csv(path, rows):
    with open(path, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(["timestamp", "user_id", "message"])
        writer.writerows(rows)

# Clean 1: multi-language, embedded newlines, distance > 2, < 50 events per 10m
base_time = datetime(2023, 10, 25, 14, 0, 0)
rows = []
for i in range(10):
    t = (base_time + timedelta(minutes=i)).strftime("%Y-%m-%dT%H:%M:%SZ")
    rows.append([t, f"user{i}", "Hello\nWorld\nこんにちは"])
write_csv(os.path.join(clean_dir, "clean1.csv"), rows)

# Evil 1: distance <= 2 to firewall (e.g. homoglyph 'fіrewall')
rows_evil1 = [
    [base_time.strftime("%Y-%m-%dT%H:%M:%SZ"), "user_evil", "fіrewall\nnewline"] # 'і' is cyrillic, distance 1
]
write_csv(os.path.join(evil_dir, "evil1.csv"), rows_evil1)

# Evil 2: > 50 events in 10m bucket
rows_evil2 = []
for i in range(51):
    t = (base_time + timedelta(seconds=i)).strftime("%Y-%m-%dT%H:%M:%SZ")
    rows_evil2.append([t, f"user{i}", "Normal message"])
write_csv(os.path.join(evil_dir, "evil2.csv"), rows_evil2)

EOF

    python3 /tmp/gen_corpus.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
