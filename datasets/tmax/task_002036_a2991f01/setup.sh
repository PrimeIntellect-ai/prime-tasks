#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/legacy_data
mkdir -p /home/user/new_data

cat << 'EOF' > /home/user/setup_data.py
import json
import zlib
import os

os.makedirs("/home/user/legacy_data", exist_ok=True)

valid_data = ["hello world", "test data 1", "data processing is fun", "software engineering", "agent training"]
invalid_data = ["corrupted string 1", "corrupted string 2"]

with open("/home/user/legacy_data/data_01.jsonl", "w") as f:
    # Write valid records
    for i, d in enumerate(valid_data):
        crc = format(zlib.crc32(d.encode('utf-8')) & 0xFFFFFFFF, '08x')
        f.write(json.dumps({"id": i, "data": d, "crc32": crc}) + "\n")

    # Write invalid records (wrong crc)
    for i, d in enumerate(invalid_data):
        f.write(json.dumps({"id": i + 100, "data": d, "crc32": "00000000"}) + "\n")

EOF

python3 /home/user/setup_data.py
rm /home/user/setup_data.py

chmod -R 777 /home/user
