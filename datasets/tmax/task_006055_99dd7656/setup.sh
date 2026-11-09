#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/data
    mkdir -p /home/user/solution

    # Generate the input data file
    python3 -c "
import struct, json, os

records = [
    {'id': 'A1', 'values': [1000000000.0, 1000000000.000001, 1000000000.000002]},
    {'id': 'B2', 'values': [5.5]},
    {'id': 'C3', 'values': [1.0, 2.0, 3.0]},
    {'id': 'D4', 'values': [10.1, 10.1, 10.1]}
]

with open('/home/user/data/inputs.dat', 'wb') as f:
    for rec in records:
        payload = json.dumps(rec).encode('utf-16le')
        f.write(struct.pack('>I', len(payload)))
        f.write(payload)
"

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
