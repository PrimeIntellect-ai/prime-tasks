#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential libssl-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/dataset/raw
    mkdir -p /home/user/dataset/backup

    cat << 'EOF' > /home/user/setup_data.py
import struct
import hashlib
import json
import os

def create_dat(filepath, timestamp, version, csv_data):
    # Header: RSCH (4) + timestamp (4) + version (2) + header_len (2)
    header = struct.pack('<4sIH H', b'RSCH', timestamp, version, 12)
    payload = csv_data.encode('utf-8')
    content = header + payload
    with open(filepath, 'wb') as f:
        f.write(content)
    return hashlib.sha256(content).hexdigest()

csv1 = "record_id,sensor_value,status\n1,10.5,ok\n2,12.5,ok\n" # avg: 11.50
csv2 = "record_id,sensor_value,status\n1,5.0,ok\n2,7.0,ok\n3,3.0,err\n" # avg: 5.00
csv3 = "record_id,sensor_value,status\n1,20.0,ok\n2,30.0,ok\n" # avg: 25.00
csv4 = "record_id,sensor_value,status\n1,100.1,ok\n2,200.2,ok\n" # avg: 150.15

# file1 and file2 will be "already backed up"
hash1 = create_dat('/home/user/dataset/backup/data1.dat', 1600000000, 1, csv1)
hash2 = create_dat('/home/user/dataset/backup/data2.dat', 1600000100, 1, csv2)

# file1, file3, file4 will be in raw. file1 is a duplicate.
create_dat('/home/user/dataset/raw/data1.dat', 1600000000, 1, csv1)
hash3 = create_dat('/home/user/dataset/raw/data3.dat', 1600000200, 1, csv3)
hash4 = create_dat('/home/user/dataset/raw/data4.dat', 1600000300, 1, csv4)

# Create initial manifest
manifest_path = '/home/user/dataset/backup/manifest.jsonl'
with open(manifest_path, 'w') as f:
    f.write(json.dumps({"file": "data1.dat", "sha256": hash1, "timestamp": 1600000000, "avg": 11.5}) + "\n")
    f.write(json.dumps({"file": "data2.dat", "sha256": hash2, "timestamp": 1600000100, "avg": 5.0}) + "\n")
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    chmod -R 777 /home/user
