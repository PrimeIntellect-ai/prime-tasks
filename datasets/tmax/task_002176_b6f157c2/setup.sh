#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip e2fsprogs fuse2fs
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import subprocess

os.makedirs("/home/user/raw_data/payload/var/log/app1", exist_ok=True)
os.makedirs("/home/user/raw_data/payload/etc/cron", exist_ok=True)

log1_data = [
    "{'timestamp': '2023-10-01T10:00:00', 'level': 'INFO', 'service': 'app1', 'message': 'Started'}!!!\n",
    "{'timestamp': '2023-10-01T10:05:00', 'level': 'FATAL', 'service': 'app1', 'message': 'Memory corruption detected'}!!!\n"
]
log2_data = [
    "{'timestamp': '2023-10-01T10:10:00', 'level': 'WARN', 'service': 'cron', 'message': 'Slow execution'}!!!\n",
    "{'timestamp': '2023-10-01T10:15:00', 'level': 'FATAL', 'service': 'cron', 'message': 'Disk full'}!!!\n"
]

with open("/home/user/raw_data/payload/var/log/app1/app1.log.chunk1", "w") as f:
    f.write(log1_data[0])
with open("/home/user/raw_data/payload/var/log/app1/app1.log.chunk2", "w") as f:
    f.write(log1_data[1])

with open("/home/user/raw_data/payload/etc/cron/cron.log.chunk2", "w") as f:
    f.write(log2_data[1])
with open("/home/user/raw_data/payload/etc/cron/cron.log.chunk1", "w") as f:
    f.write(log2_data[0])

# Create image without needing loop mount
subprocess.run(["mke2fs", "-d", "/home/user/raw_data", "-t", "ext4", "/home/user/suspect_data.img", "64M"])
subprocess.run(["chown", "user:user", "/home/user/suspect_data.img"])
subprocess.run(["rm", "-rf", "/home/user/raw_data"])
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
