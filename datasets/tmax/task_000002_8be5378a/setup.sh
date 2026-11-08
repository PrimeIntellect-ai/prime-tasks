#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip espeak
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /app
espeak -w /app/voicemail.wav "I need to report a bug in the production system."

cat << 'EOF' > /home/user/aligner.py
import sys

def main():
    text = sys.stdin.read().strip()
    if not text:
        return
    words = text.split()

    chunks = []
    for i in range(0, len(words), 3):
        chunk = words[i:i+3]
        # Bug: off-by-one/IndexError when trying to pad
        if len(chunk) < 3:
            missing = 3 - len(chunk)
            for j in range(missing):
                # This causes an IndexError if words is exhausted
                chunk.append(words[i + 3 + j]) 
        chunks.append("-".join(chunk))

    for c in chunks:
        print(c)

if __name__ == "__main__":
    main()
EOF

cat << 'EOF' > /app/oracle_aligner.py
#!/usr/bin/env python3
import sys

def main():
    text = sys.stdin.read().strip()
    if not text:
        return
    words = text.split()

    chunks = []
    for i in range(0, len(words), 3):
        chunk = words[i:i+3]
        while len(chunk) < 3:
            chunk.append("SILENCE")
        chunks.append("-".join(chunk))

    for c in chunks:
        print(c)

if __name__ == "__main__":
    main()
EOF
chmod +x /app/oracle_aligner.py

chmod -R 777 /home/user
