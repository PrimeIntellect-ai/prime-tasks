#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    # Create directories
    mkdir -p /app/audio
    mkdir -p /app/data/corpus/clean
    mkdir -p /app/data/corpus/evil

    # Generate audio file
    espeak -w /app/audio/sysadmin_memo.wav "Please ensure the default load factor is set to zero point eight five."

    # Generate JSON data
    python3 -c '
import json
import uuid
import random
import os

def generate_clean():
    for i in range(10):
        records = []
        for j in range(5):
            records.append({
                "record_id": str(uuid.uuid4()),
                "timestamp": 1690000000.0 + j * 10.0,
                "metrics": [random.random() for _ in range(4)],
                "load_factor": None if random.random() < 0.5 else random.random()
            })
        with open(f"/app/data/corpus/clean/clean_{i}.json", "w") as f:
            json.dump(records, f)

def generate_evil():
    for i in range(10):
        records = []
        base_t = 1690000000.0
        base_m = [0.5, 0.5, 0.5, 0.5]
        records.append({
            "record_id": str(uuid.uuid4()),
            "timestamp": base_t,
            "metrics": base_m,
            "load_factor": None
        })
        records.append({
            "record_id": str(uuid.uuid4()),
            "timestamp": base_t + 1.0,
            "metrics": [m + 0.01 for m in base_m],
            "load_factor": None
        })
        for j in range(3):
            records.append({
                "record_id": str(uuid.uuid4()),
                "timestamp": base_t + 10.0 + j * 10.0,
                "metrics": [random.random() for _ in range(4)],
                "load_factor": None
            })
        with open(f"/app/data/corpus/evil/evil_{i}.json", "w") as f:
            json.dump(records, f)

generate_clean()
generate_evil()
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
