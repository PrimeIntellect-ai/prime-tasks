#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/service_a.py
import os, time, sys
if os.environ.get("API_KEY") != "sre_monitor_99":
    sys.exit(1)
while True:
    time.sleep(1)
EOF

cat << 'EOF' > /home/user/service_b.py
import time, sys
while True:
    print("Log line to trigger rotation quickly... " * 10)
    sys.stdout.flush()
    time.sleep(0.2)
EOF

chmod -R 777 /home/user
