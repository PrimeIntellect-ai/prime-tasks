#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/instances/inst1 \
             /home/user/instances/inst2 \
             /home/user/instances/inst3 \
             /home/user/instances/inst4 \
             /home/user/instances/inst5

    for i in 1 2 3 4 5; do
        echo '{"version": "1.0", "theme": "blue"}' > "/home/user/instances/inst${i}/config.json"
    done

    cat << 'EOF' > /home/user/validate.py
import sys
import json
import os

if len(sys.argv) != 2:
    sys.exit(1)

inst_dir = sys.argv[1]
config_path = os.path.join(inst_dir, 'config.json')

if not os.path.exists(config_path):
    sys.exit(1)

with open(config_path, 'r') as f:
    data = json.load(f)

# Rig inst4 to fail on version 2.0
if os.path.basename(inst_dir) == 'inst4' and data.get('version') == '2.0':
    sys.exit(1)

sys.exit(0)
EOF

    chmod +x /home/user/validate.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
