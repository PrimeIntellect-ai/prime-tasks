#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip curl openssl
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/mailing_lists
mkdir -p /home/user/certs

echo "alice@example.com" > /home/user/mailing_lists/alice.list_config
echo "bob@example.com" > /home/user/mailing_lists/bob.list_config
echo "charlie@example.com" > /home/user/mailing_lists/charlie.list_config
echo "diana@example.com" > /home/user/mailing_lists/diana.list_config

cat << 'EOF' > /home/user/monitor.py
#!/usr/bin/env python3
import os
import json
import time
import glob

while True:
    data = {}
    for filepath in glob.glob('/home/user/mailing_lists/*.list_config'):
        # Security check: skip if permissions are not exactly 0600
        st = os.stat(filepath)
        if (st.st_mode & 0o777) != 0o600:
            continue

        user = os.path.basename(filepath).split('.')[0]
        with open(filepath, 'r') as f:
            data[user] = f.read().strip()

    with open('/home/user/status.json', 'w') as f:
        json.dump(data, f)

    time.sleep(2)
EOF

chmod -R 777 /home/user

chmod 0600 /home/user/mailing_lists/alice.list_config
chmod 0644 /home/user/mailing_lists/bob.list_config
chmod 0664 /home/user/mailing_lists/charlie.list_config
chmod 0660 /home/user/mailing_lists/diana.list_config
