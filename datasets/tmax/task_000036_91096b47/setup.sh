#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

# Create directories and files using python to ensure exact byte sequences
python3 -c '
import os

os.makedirs("/home/user/project_assets", exist_ok=True)
os.makedirs("/home/user/organized/bin", exist_ok=True)
os.makedirs("/home/user/organized/txt", exist_ok=True)

with open("/home/user/project_assets/config.json", "w") as f:
    f.write("{\"status\": \"ok\", \"port\": 8080}\n")

with open("/home/user/project_assets/readme.md", "w") as f:
    f.write("# Project Readme\n")

with open("/home/user/project_assets/script.py", "w") as f:
    f.write("def hello(): print(\"world\")\n")

with open("/home/user/project_assets/logo.gif", "wb") as f:
    f.write(b"GIF89a\x00\x01\x00\x01\x00\x00\x00")

with open("/home/user/project_assets/executable.bin", "wb") as f:
    f.write(b"\x7FELF\x02\x01\x01\x00\x00\x00\x00\x00")

with open("/home/user/project_assets/mixed.dat", "wb") as f:
    f.write(b"Some prefix text\x00and then binary")
'

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
