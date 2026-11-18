#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os

os.makedirs('/home/user/artifacts', exist_ok=True)

with open('/home/user/artifacts/file1.bin', 'wb') as f:
    f.write(b'\xCA\xFE\xBA\xBE\x01\x02\x03')

with open('/home/user/artifacts/file2.bin', 'wb') as f:
    f.write(b'\x00\x00\x00\x00\x01\x02\x03')

with open('/home/user/artifacts/file3.bin', 'wb') as f:
    f.write(b'\x12\x34\x56\x78\x00\x00')

with open('/home/user/repo.log', 'wb') as f:
    f.write(b"BEGIN ARTIFACT\n")
    f.write(b"File: file1.bin\n")
    f.write(b"Magic: CAFEBABE\n")
    f.write(b"Desc: First valid file\n")
    f.write(b"END ARTIFACT\n")
    f.write(b"BEGIN ARTIFACT\n")
    f.write(b"File: file2.bin\n")
    f.write(b"Magic: DEADBEEF\n")
    f.write(b"Desc: Corrupted file\n")
    f.write(b"END ARTIFACT\n")
    f.write(b"BEGIN ARTIFACT\n")
    f.write(b"File: file3.bin\n")
    f.write(b"Magic: 12345678\n")
    f.write(b"Desc: Third valid file with special char: \xC9\n")
    f.write(b"END ARTIFACT\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
