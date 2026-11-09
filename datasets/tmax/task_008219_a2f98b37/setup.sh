#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup.py
import json

csv_data = [
    "2023:05:01-10:00:00,btn_start,Hello",
    "2023:05:01-10:05:00,btn_cancel,Cancel",
    "2023:05:01-10:10:00,btn_save,Save",
    "2023:05:01-10:15:00,btn_exit,Exit"
]

jsonl_data = [
    # Time diff: 4s, distance: Hello (5) vs Héllo (H \xc3\xa9 l l o = 6 bytes) -> Levenshtein distance 2. Match!
    {"ts": "2023-05-01T10:00:04Z", "key": "start_btn", "src": "H\u00e9llo"},
    # Time diff: 10s -> Fails time check
    {"ts": "2023-05-01T10:05:10Z", "key": "cancel_btn", "src": "Cancel"},
    # Time diff: 2s, distance: Save (4) vs Sávé (S \xc3\xa1 v \xc3\xa9 = 6 bytes) -> Distance 2. Match!
    {"ts": "2023-05-01T10:10:02Z", "key": "save_btn", "src": "S\u00e1v\u00e9"},
    # Time diff: 0s, distance: Exit (4) vs Quittttt (8) -> Distance 4. Fails distance check
    {"ts": "2023-05-01T10:15:00Z", "key": "exit_btn", "src": "Quittttt"}
]

with open('/home/user/service_a.csv', 'w', encoding='utf-8') as f:
    for line in csv_data:
        f.write(line + '\n')

with open('/home/user/service_b.jsonl', 'w', encoding='ascii') as f:
    for obj in jsonl_data:
        f.write(json.dumps(obj) + '\n')
EOF

    python3 /home/user/setup.py

    chmod -R 777 /home/user
