#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install pytest

    mkdir -p /app
    espeak -w /app/project_dictation.wav "The XOR passphrase for the archive is 'omega99'. Move all files with a dot log extension into a folder named logs. Move all python files into a folder named src. Leave everything else in the root."

    cat << 'EOF' > /tmp/setup.py
import os
import tarfile

os.makedirs('/tmp/proj', exist_ok=True)
with open('/tmp/proj/app.log', 'w') as f: f.write('log data')
with open('/tmp/proj/main.py', 'w') as f: f.write('print("hello")')
with open('/tmp/proj/README.md', 'w') as f: f.write('readme')

with tarfile.open('/tmp/archive.tar.gz', 'w:gz') as tar:
    tar.add('/tmp/proj/app.log', arcname='app.log')
    tar.add('/tmp/proj/main.py', arcname='main.py')
    tar.add('/tmp/proj/README.md', arcname='README.md')

with open('/tmp/archive.tar.gz', 'rb') as f:
    data = f.read()

key = b'omega99'
enc = bytes([b ^ key[i % len(key)] for i, b in enumerate(data)])

os.makedirs('/home/user/project_parts', exist_ok=True)
chunk_size = 100
for i in range(0, len(enc), chunk_size):
    part_num = (i // chunk_size) + 1
    with open(f'/home/user/project_parts/archive.dat.part{part_num}', 'wb') as f:
        f.write(enc[i:i+chunk_size])
EOF

    python3 /tmp/setup.py
    rm -rf /tmp/proj /tmp/archive.tar.gz /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
