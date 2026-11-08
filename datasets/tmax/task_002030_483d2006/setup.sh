#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg espeak-ng
pip3 install pytest

mkdir -p /app

# Generate the voicemail audio file using espeak-ng
espeak-ng -w /app/voicemail.wav "Hey, it's Dave from IT. For those old dat archives, the text payload always starts at byte offset five hundred and twelve. The encoding is CP zero three seven. Make sure you replace all instances of the word ERROR with RESOLVED in uppercase before saving."

# Create the oracle extractor script
cat << 'EOF' > /app/oracle_extractor.py
#!/usr/bin/env python3
import sys

def main():
    if len(sys.argv) != 2:
        sys.exit(1)

    with open(sys.argv[1], 'rb') as f:
        f.seek(512)
        payload = f.read()

    decoded = payload.decode('cp037')
    cleaned = decoded.replace('ERROR', 'RESOLVED')
    print(cleaned, end='')

if __name__ == '__main__':
    main()
EOF

chmod +x /app/oracle_extractor.py

# Create user and set permissions
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user /app
