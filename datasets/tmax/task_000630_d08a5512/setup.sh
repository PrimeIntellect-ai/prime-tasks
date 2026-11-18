#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest psutil

useradd -m -s /bin/bash user || true

mkdir -p /home/user/data /home/user/backup
echo "metric1,100" > /home/user/data/metric1.csv
echo "metric2,200" > /home/user/data/metric2.csv
echo "999999" > /home/user/app.pid

cat << 'EOF' > /home/user/worker.py
#!/usr/bin/env python3
import os
import time

pid = os.getpid()
with open("/home/user/app.pid", "w") as f:
    f.write(str(pid))

# Simulate long running process
time.sleep(10000)
EOF

chmod +x /home/user/worker.py
chmod -R 777 /home/user
