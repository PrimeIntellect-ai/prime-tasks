#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs

    python3 -c '
import os
import json

os.makedirs("/home/user/logs", exist_ok=True)

events = [
    {"timestamp": "2023-10-01T10:00:00", "event_id": "evt-001", "user_id": 101, "payload": "start process", "retry_count": 0},
    {"timestamp": "2023-10-01T10:05:00", "event_id": "evt-002", "user_id": 102, "payload": "load data \xff corrupted", "retry_count": 0},
    {"timestamp": "2023-10-01T10:10:00", "event_id": "evt-003", "user_id": 103, "payload": "transform", "retry_count": 0},
    {"timestamp": "2023-10-01T10:00:00", "event_id": "evt-001", "user_id": 101, "payload": "start process", "retry_count": 1},
    {"timestamp": "2023-10-01T10:05:00", "event_id": "evt-002", "user_id": 102, "payload": "load data \xff corrupted", "retry_count": 2},
    {"timestamp": "2023-10-01T10:15:00", "event_id": "evt-004", "user_id": 104, "payload": "end process", "retry_count": 0},
    {"timestamp": "2023-10-01T10:15:00", "event_id": "evt-004", "user_id": 104, "payload": "end process", "retry_count": 3},
]

file_distributions = [
    [0, 1],
    [2, 3],
    [4, 5],
    [1, 6]
]

for i, dist in enumerate(file_distributions):
    with open(f"/home/user/logs/etl_retry_{i}.log", "wb") as f:
        for idx in dist:
            record = events[idx].copy()
            payload_raw = record["payload"]
            record["payload"] = "PLACEHOLDER"
            json_bytes = json.dumps(record).encode("utf-8")
            if "\xff" in payload_raw:
                json_bytes = json_bytes.replace(b"\"PLACEHOLDER\"", b"\"load data \xff corrupted\"")
            else:
                json_bytes = json_bytes.replace(b"\"PLACEHOLDER\"", b"\"" + payload_raw.encode("utf-8") + b"\"")
            f.write(json_bytes + b"\n")
'

    chmod -R 777 /home/user
