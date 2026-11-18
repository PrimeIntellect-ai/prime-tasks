#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc espeak
    pip3 install pytest

    mkdir -p /app/audio
    espeak -w /app/audio/rule.wav "The configuration sanitizer must reject any stream that contains the exact sequence of bytes zero x DE zero x AD zero x BE zero x EF anywhere in the payload, and it must also block any BACKUP directive that targets the slash root directory."

    cat << 'EOF' > /tmp/gen_corpus.py
import os
import random

os.makedirs('/app/corpus/clean', exist_ok=True)
os.makedirs('/app/corpus/evil', exist_ok=True)

# Generate Clean Corpus
for i in range(50):
    with open(f'/app/corpus/clean/clean_{i}.bin', 'wb') as f:
        f.write(b"BACKUP /etc/nginx/nginx.conf\n")
        f.write(b"SYMLINK /backup/config/target /backup/config/link\n")
        # Add random safe binary data
        f.write(os.urandom(100).replace(b'\xde\xad\xbe\xef', b'\x00\x00\x00\x00'))

# Generate Evil Corpus
evil_conditions = [
    b"BACKUP /root/secrets.txt\n",
    b"some data \xde\xad\xbe\xef more data",
    b"SYMLINK /etc/passwd /backup/config/passwd\n",
    b"HARDLINK /var/log/auth.log /backup/config/auth.log\n"
]

for i in range(50):
    with open(f'/app/corpus/evil/evil_{i}.bin', 'wb') as f:
        # Ensure each evil condition is represented
        f.write(evil_conditions[i % len(evil_conditions)])
        f.write(os.urandom(50))
EOF

    python3 /tmp/gen_corpus.py
    rm /tmp/gen_corpus.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
