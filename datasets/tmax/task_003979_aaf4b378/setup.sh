#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg fonts-dejavu-core build-essential
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate payloads
    python3 -c "
import os, base64
key = b'SecretKeyAabcd1234'
def encrypt(data):
    return base64.b64encode(bytes([data[i] ^ key[i % len(key)] for i in range(len(data))])).decode('utf-8')

for i in range(50):
    clean_data = b'{\"status\": \"ok\", \"id\": ' + str(i).encode() + b'}'
    with open(f'/app/corpus/clean/payload_{i}.txt', 'w') as f: f.write(encrypt(clean_data))

    evil_data = b'{\"cmd\": \"EXEC_SHELL\", \"id\": ' + str(i).encode() + b'}' if i % 2 == 0 else b'{\"file\": \"../../etc/passwd\", \"id\": ' + str(i).encode() + b'}'
    with open(f'/app/corpus/evil/payload_{i}.txt', 'w') as f: f.write(encrypt(evil_data))
"

    # Generate video
    ffmpeg -f lavfi -i color=c=black:s=640x480:d=16 -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='U2VjcmV0S2V5QWFiY2QxMjM0=':fontcolor=white:fontsize=24:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,12,15)'" -c:v libx264 -pix_fmt yuv420p /app/evidence.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
