#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/project_dump

    python3 -c "
import os

dump_dir = '/home/user/project_dump'
os.makedirs(dump_dir, exist_ok=True)

with open(os.path.join(dump_dir, 'logo.dat'), 'wb') as f:
    f.write(b'\x89\x50\x4E\x47\x0D\x0A\x1A\x0A\x00\x00\x00\x0D\x49\x48\x44\x52')

with open(os.path.join(dump_dir, 'archive.tmp'), 'wb') as f:
    f.write(b'\x1F\x8B\x08\x00\x00\x00\x00\x00\x00\x03\x4B\xCB\xCF\x07\x00')

with open(os.path.join(dump_dir, 'document'), 'wb') as f:
    f.write(b'\x25\x50\x44\x46\x2D\x31\x2E\x34\x0A\x25\xE2\xE3\xCF\xD3')

with open(os.path.join(dump_dir, 'notes.bin'), 'wb') as f:
    f.write(b'This is just a standard text file.\nNothing special here.\n')
"

    chmod -R 777 /home/user
