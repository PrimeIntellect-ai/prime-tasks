#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_configs

    cat << 'EOF' > /home/user/setup_raw_configs.py
import json
import os

configs = [
    {"server_id": "srv-alpha", "timestamp": 1682001000, "hardware": {"ram_gb": 16, "cpu_cores": 4}, "software": {"os": "ubuntu-22.04", "is_active": "true"}},
    {"server_id": "srv-alpha", "timestamp": 1682004600, "hardware": {"ram_gb": 32, "cpu_cores": 4}, "software": {"os": "ubuntu-22.04", "is_active": "false"}},
    {"server_id": "srv-alpha", "timestamp": 1682008200, "hardware": {"ram_gb": 32, "cpu_cores": 8}, "software": {"os": "ubuntu-22.04", "is_active": "true"}},
    {"server_id": "srv-beta", "timestamp": 1682001000, "hardware": {"ram_gb": 8, "cpu_cores": 2}, "software": {"os": "centos-7", "is_active": "false"}},
    {"server_id": "srv-beta", "timestamp": 1682004600, "hardware": {"ram_gb": 8, "cpu_cores": 2}, "software": {"os": "centos-7", "is_active": "false"}},
    {"server_id": "srv-gamma", "timestamp": 1682001000, "hardware": {"ram_gb": 64, "cpu_cores": 16}, "software": {"os": "debian-11", "is_active": "true"}},
]

for i, conf in enumerate(configs):
    with open(f"/home/user/raw_configs/config_{i}.json", "w") as f:
        json.dump(conf, f)
EOF

    python3 /home/user/setup_raw_configs.py

    chmod -R 777 /home/user
