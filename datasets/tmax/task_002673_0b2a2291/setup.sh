#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    cat << 'EOF' > /tmp/setup_corpus.py
import struct
import os

def create_archive(path, entries):
    with open(path, 'wb') as f:
        for name, data in entries:
            encoded_name = name.encode('ascii')
            f.write(struct.pack('<H', len(encoded_name)))
            f.write(encoded_name)
            f.write(struct.pack('<I', len(data)))
            f.write(data)

with open('/app/video.mp4', 'wb') as f:
    f.write(os.urandom(1024 * 1024)) # 1MB fake video

with open('/app/video.mp4', 'rb') as f:
    video_data = f.read()

create_archive('/app/corpus/clean/test1.bin', [
    ('chunk1.mp4', video_data[:1000]),
    ('data/chunk2.mp4', video_data[1000:2000])
])

create_archive('/app/corpus/evil/test1.bin', [
    ('chunk1.mp4', video_data[:500]),
    ('../etc/passwd', b'evil data')
])

create_archive('/app/corpus/evil/test2.bin', [
    ('/tmp/pwned', b'more evil data')
])

create_archive('/app/corpus/evil/test3.bin', [
    ('data/../../root/.bashrc', b'evil bashrc')
])
EOF

    python3 /tmp/setup_corpus.py
    rm /tmp/setup_corpus.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
