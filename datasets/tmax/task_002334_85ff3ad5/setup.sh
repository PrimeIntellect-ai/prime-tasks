#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup.py
import os
import tarfile
import json
import io

# Setup directories
dirs = [
    "/home/user/incoming",
    "/home/user/extracted",
    "/home/user/configs"
]
for d in dirs:
    os.makedirs(d, exist_ok=True)

# Create Bundle 1 (Valid)
os.makedirs("/tmp/bundle1", exist_ok=True)
with open("/tmp/bundle1/app.conf", "w") as f:
    f.write("port=8080\nenable_feature=true\n")
with open("/tmp/bundle1/deploy.json", "w") as f:
    json.dump({"deploy": ["app.conf"]}, f)

with tarfile.open("/home/user/incoming/bundle1.tar.gz", "w:gz") as tar:
    tar.add("/tmp/bundle1/app.conf", arcname="app.conf")
    tar.add("/tmp/bundle1/deploy.json", arcname="deploy.json")

# Create Bundle 2 (Malicious Zip Slip attempt)
os.makedirs("/tmp/bundle2", exist_ok=True)
with open("/tmp/bundle2/hacked.txt", "w") as f:
    f.write("YOU HAVE BEEN HACKED\n")
with open("/tmp/bundle2/deploy.json", "w") as f:
    json.dump({"deploy": ["hacked.txt"]}, f)

with tarfile.open("/home/user/incoming/bundle2.tar.gz", "w:gz") as tar:
    # Add a normal deploy.json
    tar.add("/tmp/bundle2/deploy.json", arcname="deploy.json")

    # Add a malicious path
    info = tarfile.TarInfo(name="../../../home/user/configs/hacked.txt")
    with open("/tmp/bundle2/hacked.txt", "rb") as f:
        content = f.read()
    info.size = len(content)
    tar.addfile(info, io.BytesIO(content))
EOF

python3 /tmp/setup.py
rm -rf /tmp/bundle1 /tmp/bundle2 /tmp/setup.py

chmod -R 777 /home/user
