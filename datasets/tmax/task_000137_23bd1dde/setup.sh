#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak-ng gcc
    pip3 install pytest

    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Generate voicemail
    espeak-ng -w /app/voicemail.wav "The legacy system asserts when the precision delta exceeds zero point zero zero seven five."

    # Generate corpora and crash dump
    python3 -c "
import os
import struct
import random

# Generate clean files
for i in range(5):
    with open(f'/app/corpora/clean/clean_{i}.bin', 'wb') as f:
        for _ in range(10000):
            f.write(struct.pack('<f', 0.0001))

# Generate evil files
for i in range(5):
    with open(f'/app/corpora/evil/evil_{i}.bin', 'wb') as f:
        f.write(struct.pack('<f', 1000000.0))
        for _ in range(10000):
            f.write(struct.pack('<f', 0.01))

# Generate crash dump
with open('/app/crash.dmp', 'wb') as f:
    f.write(os.urandom(1024))
    f.write(b'\x00/app/corpora/clean/\x00')
    f.write(os.urandom(512))
    f.write(b'\x00/app/corpora/evil/\x00')
    f.write(os.urandom(1024))
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
