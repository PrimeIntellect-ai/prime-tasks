#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    mkdir -p /app
    echo "seven three nine one four" | espeak -w /app/key_audio.wav

    cat << 'EOF' > /app/obfuscated_encoder.py
import sys, binascii
def e(s, k):
    return binascii.hexlify(bytes([s[i] ^ ord(str(k)[i % len(str(k))]) for i in range(len(s))])).decode('utf-8')
# usage: print(e(sys.stdin.read().encode('utf-8'), 73914))
EOF

    cat << 'EOF' > /app/oracle_encoder.py
#!/usr/bin/env python3
import sys
import binascii

def encode(data: bytes, key: str) -> str:
    res = []
    for i in range(len(data)):
        res.append(data[i] ^ ord(key[i % len(key)]))
    return binascii.hexlify(bytes(res)).decode('utf-8')

if __name__ == '__main__':
    data = sys.stdin.read().encode('utf-8')
    # Key extracted from audio
    print(encode(data, "73914"), end='')
EOF
    chmod +x /app/oracle_encoder.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
