#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/project/alpha
    mkdir -p /home/user/project/beta
    mkdir -p /home/user/project/gamma
    mkdir -p /home/user/project/delta
    mkdir -p /home/user/project/epsilon

    cat << 'EOF' > /home/user/setup_project.py
import json
import binascii
import base64
import os

packages = {
    "alpha": {"name": "alpha", "deps": []},
    "beta": {"name": "beta", "deps": ["alpha"]},
    "gamma": {"name": "gamma", "deps": ["beta", "delta"]},
    "delta": {"name": "delta", "deps": ["alpha"]},
    "epsilon": {"name": "epsilon", "deps": ["gamma"]}
}

for d, data in packages.items():
    json_str = json.dumps(data)
    hex_str = binascii.hexlify(json_str.encode('utf-8')).decode('utf-8')
    b64_str = base64.b64encode(hex_str.encode('utf-8')).decode('utf-8')

    with open(f"/home/user/project/{d}/meta.dat", "w") as f:
        f.write(b64_str)

EOF

    python3 /home/user/setup_project.py
    rm /home/user/setup_project.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
