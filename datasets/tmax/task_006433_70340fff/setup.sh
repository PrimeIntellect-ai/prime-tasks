#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev tar gzip jq
    pip3 install pytest

    mkdir -p /home/user

    python3 -c '
import tarfile
import os
import shutil

input_dir = "/home/user/legacy_input"
os.makedirs(input_dir, exist_ok=True)

data = {
    "app1.conf": "[General]\nName=Café\nLocation=Montréal\n[Network]\nHost=españa.local\n",
    "app2.conf": "[Users]\nAdmin=François\nGuest=Jürgen\n[Access]\nRole=Naïve\n"
}

for name, content in data.items():
    with open(os.path.join(input_dir, name), "wb") as f:
        f.write(content.encode("iso-8859-1"))

with tarfile.open("/home/user/legacy_configs.tar.gz", "w:gz") as tar:
    tar.add(input_dir, arcname="legacy_input")

shutil.rmtree(input_dir)
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
