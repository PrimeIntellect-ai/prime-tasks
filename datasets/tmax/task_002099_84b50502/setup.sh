#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        ffmpeg \
        tesseract-ocr \
        fonts-dejavu-core

    pip3 install pytest

    mkdir -p /app

    # Create c2_crypto.py
    cat << 'EOF' > /app/c2_crypto.py
import base64
def encrypt(data: bytes, key: str) -> bytes:
    key_bytes = key.encode()
    xored = bytes(a ^ key_bytes[i % len(key_bytes)] for i, a in enumerate(data))
    return base64.b64encode(xored)

def decrypt(data: bytes, key: str) -> bytes:
    raw = base64.b64decode(data)
    key_bytes = key.encode()
    return bytes(a ^ key_bytes[i % len(key_bytes)] for i, a in enumerate(raw))
EOF

    # Compile c2_crypto.py to .pyc and remove the source
    python3 -c "import py_compile; py_compile.compile('/app/c2_crypto.py', cfile='/app/c2_crypto.pyc')"
    rm /app/c2_crypto.py

    # Generate the evaluation corpora
    python3 -c "
import os, base64

def encrypt(data: bytes, key: str) -> bytes:
    key_bytes = key.encode()
    xored = bytes(a ^ key_bytes[i % len(key_bytes)] for i, a in enumerate(data))
    return base64.b64encode(xored)

os.makedirs('/app/eval_corpus/evil', exist_ok=True)
os.makedirs('/app/eval_corpus/clean', exist_ok=True)

key = 'Sup3rS3cr3tX0R'
evil1 = b'CMD: C2_EXEC whoami'
evil2 = b'DATA: EXFILTRATE /etc/shadow'
clean1 = b'INFO: Heartbeat'
clean2 = b'DATA: status=OK'

with open('/app/eval_corpus/evil/payload1.txt', 'wb') as f: f.write(encrypt(evil1, key))
with open('/app/eval_corpus/evil/payload2.txt', 'wb') as f: f.write(encrypt(evil2, key))
with open('/app/eval_corpus/clean/payload1.txt', 'wb') as f: f.write(encrypt(clean1, key))
with open('/app/eval_corpus/clean/payload2.txt', 'wb') as f: f.write(encrypt(clean2, key))
"

    # Generate the video
    ffmpeg -f lavfi -i color=c=black:s=640x480:r=1:d=5 -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='export C2_KEY=Sup3rS3cr3tX0R':fontcolor=white:fontsize=24:x=10:y=10:enable='between(t,2,3)'" -c:v libx264 -y /app/c2_session.mp4

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
