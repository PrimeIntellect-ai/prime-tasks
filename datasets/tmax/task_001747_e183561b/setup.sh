#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git espeak
    pip3 install pytest

    mkdir -p /app/repo
    cd /app/repo
    git init
    git config user.email "legacy@example.com"
    git config user.name "Legacy Engineer"

    cat << 'EOF' > requirements.txt
numpy>=2.0.0
numpy<1.20
EOF

    cat << 'EOF' > processor.py
import sys
import numpy as np

# MAGIC_CONSTANT = ??? # Check voicemail
MAGIC_CONSTANT = 0

def main():
    line = sys.stdin.read().strip()
    if not line: return
    samples = np.array([int(x) for x in line.split(',')], dtype=np.int16)
    c = np.int16(MAGIC_CONSTANT)
    # Bug: overflow happens here before division
    out = (samples * c) // np.int16(256)
    print(','.join(map(str, out)))

if __name__ == '__main__':
    main()
EOF

    git add requirements.txt processor.py
    git commit -m "Initial commit with legacy audio processor"

    rm processor.py
    git add -u
    git commit -m "Accidentally delete processor script"

    cat << 'EOF' > /app/oracle_processor.py
#!/usr/bin/env python3
import sys

def main():
    line = sys.stdin.read().strip()
    if not line: return
    samples = [int(x) for x in line.split(',')]
    out = [(s * 15420) // 256 for s in samples]
    print(','.join(map(str, out)))

if __name__ == '__main__':
    main()
EOF
    chmod +x /app/oracle_processor.py

    espeak -w /app/voicemail.wav "Hey, I figured out the scaling factor. The magic constant is fifteen thousand four hundred and twenty."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
