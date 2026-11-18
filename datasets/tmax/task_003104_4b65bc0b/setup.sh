#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        golang-go \
        imagemagick \
        ghostscript \
        gsfonts \
        tesseract-ocr \
        tesseract-ocr-eng \
        nasm \
        ca-certificates

    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate the image note
    convert -background white -fill black -pointsize 24 label:"Python 3 Migration Blocker. Reject any payloads containing:\nxor eax, eax\npush eax\npush 0x68732f2f" /app/malware_note.png

    # Generate corpus using Python to ensure exact byte sequences
    python3 -c '
import os

os.makedirs("/app/corpus/clean", exist_ok=True)
os.makedirs("/app/corpus/evil", exist_ok=True)

malicious_seq = b"\x31\xc0\x50\x68\x2f\x2f\x73\x68"

for i in range(1, 21):
    with open(f"/app/corpus/clean/file_{i}.bin", "wb") as f:
        f.write(os.urandom(1024))

    with open(f"/app/corpus/evil/file_{i}.bin", "wb") as f:
        f.write(os.urandom(512) + malicious_seq + os.urandom(512))
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
