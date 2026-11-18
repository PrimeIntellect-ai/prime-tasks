#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/.config/finops

    cat << 'EOF' > /home/user/cost_analyzer.py
#!/usr/bin/env python3
import time, sys, os

heartbeat_file = "/home/user/heartbeat.txt"
behavior_file = "/home/user/cost_analyzer_behavior.txt"

try:
    with open(behavior_file, "r") as f:
        behavior = f.read().strip()
except:
    behavior = "normal"

with open(heartbeat_file, "w") as f:
    f.write(str(time.time()))

if behavior == "crash":
    time.sleep(1)
    sys.exit(1)
elif behavior == "hang":
    time.sleep(1)
    time.sleep(100)
else:
    while True:
        with open(heartbeat_file, "w") as f:
            f.write(str(time.time()))
        time.sleep(1)
EOF

    chmod +x /home/user/cost_analyzer.py
    echo "crash" > /home/user/cost_analyzer_behavior.txt

    chmod -R 777 /home/user
