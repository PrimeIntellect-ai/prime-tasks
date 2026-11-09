#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    python3 -c '
import os

os.makedirs("/home/user/raw_data/alpha", exist_ok=True)
os.makedirs("/home/user/raw_data/beta/nested", exist_ok=True)

with open("/home/user/raw_data/alpha/log1.win1252.txt", "wb") as f:
    f.write(bytes.fromhex("54 65 6d 70 65 72 61 74 75 72 65 3a 20 32 35 b0 43"))

with open("/home/user/raw_data/alpha/log2.utf8.txt", "wb") as f:
    f.write(bytes.fromhex("53 74 61 74 75 73 3a 20 4f 4b 20 e2 9c 93"))

with open("/home/user/raw_data/beta/nested/log3.utf16le.txt", "wb") as f:
    f.write(bytes.fromhex("57 00 61 00 72 00 6e 00 69 00 6e 00 67 00 3a 00 20 00 0a 00 4c 00 6f 00 77 00 20 00 62 00 61 00 74 00 74 00 65 00 72 00 79 00"))
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
