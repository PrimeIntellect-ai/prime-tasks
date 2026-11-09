#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    mkdir -p /app/corpora/evil
    mkdir -p /app/corpora/clean

    # Create the audio memo
    espeak -w /app/security_memo.wav "We've analyzed the breach. You need to identify any file as compromised if its SHA256 checksum starts with the characters 'badc0de', or if the first line of the file exactly matches the string 'EVIL_SIGNATURE'."

    # Create evil files
    echo "EVIL_SIGNATURE" > /app/corpora/evil/evil_sig.txt
    echo "malicious payload" >> /app/corpora/evil/evil_sig.txt

    # Brute-force a file whose sha256 starts with 'badc0de'
    # This might take a minute or two during the build process
    python3 -c '
import hashlib
import sys
for i in range(1000000000):
    data = f"padding{i}\n".encode()
    if hashlib.sha256(data).hexdigest().startswith("badc0de"):
        with open("/app/corpora/evil/evil_hash.txt", "wb") as f:
            f.write(data)
        sys.exit(0)
'

    # Create clean files
    echo "def hello():" > /app/corpora/clean/main.py
    echo "    print('world')" >> /app/corpora/clean/main.py
    echo "Just a normal text file." > /app/corpora/clean/readme.md
    echo "Another clean file." > /app/corpora/clean/config.cfg

    # Setup user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
