#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os

base_dir = "/home/user/storage_dumps"
os.makedirs(f"{base_dir}/logs", exist_ok=True)
os.makedirs(f"{base_dir}/data/old", exist_ok=True)

content1 = "INFO: start\n[CRITICAL]\nError 1\n[END CRITICAL]\nINFO: end\n"
with open(f"{base_dir}/logs/app1.log", "w") as f:
    f.write(content1)

content2 = "INFO: start\nINFO: running\nINFO: end\n"
with open(f"{base_dir}/logs/app2.log", "w") as f:
    f.write(content2)

content3 = "[CRITICAL]\nError 2\n[END CRITICAL]\n"
with open(f"{base_dir}/data/old/app3.log", "w") as f:
    f.write(content3)

with open(f"{base_dir}/data/old/dump1.dat", "wb") as f:
    data = bytearray(2048)
    data[1024:1028] = b'\xde\xad\xbe\xef'
    f.write(data)

with open(f"{base_dir}/data/dump2.dat", "wb") as f:
    data = bytearray(2048)
    f.write(data)

with open(f"{base_dir}/data/dump3.dat", "wb") as f:
    data = bytearray(500)
    f.write(data)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
