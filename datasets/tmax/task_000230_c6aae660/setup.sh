#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/manifests/raw
    echo '{"apiVersion": "v1", "kind": "Pod", "name": "web"}' > /home/user/manifests/raw/app1.json
    echo '{"apiVersion": "v1", "kind": "Service", "name": "db"}' > /home/user/manifests/raw/app2.json

    cat << 'EOF' > /home/user/validator.py
import os
import sys

flag_file = "/home/user/.config/validator/init.flag"
if not os.path.exists(flag_file):
    print("FATAL: Missing dependency. init.flag not found.", file=sys.stderr)
    sys.exit(1)

with open(flag_file, "r") as f:
    if f.read().strip() != "READY":
        print("FATAL: init.flag does not contain READY.", file=sys.stderr)
        sys.exit(1)

active_dir = "/home/user/manifests/active"
if not os.path.exists(active_dir):
    print("FATAL: active manifests directory not found.", file=sys.stderr)
    sys.exit(1)

files = os.listdir(active_dir)
if len(files) < 2:
    print("FATAL: expected at least 2 active manifests.", file=sys.stderr)
    sys.exit(1)

print("VALIDATION_SUCCESS: All manifests are active and dependencies met.")
EOF

    chmod -R 777 /home/user
