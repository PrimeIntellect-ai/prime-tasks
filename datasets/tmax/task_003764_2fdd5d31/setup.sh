#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c "
import os
raw_file = '/home/user/raw_data.bin'
data = b'\x41\x00\x00\x00\x42\xFF\xFF\x00\x43' + (b'\x00' * 300) + b'\x44'
with open(raw_file, 'wb') as f:
    f.write(data)
"

    chmod -R 777 /home/user
