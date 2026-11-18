#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app

    # Generate the capture image
    convert -background white -fill black -font DejaVu-Sans -pointsize 24 label:"C2_SERVER: 198.51.100.44\nDECODER_KEY: 170\n" /app/capture.png

    # Create the oracle decoder
    cat << 'EOF' > /app/oracle_decoder.py
import sys
import binascii

def decode(hex_str):
    try:
        raw_bytes = binascii.unhexlify(hex_str)
        decoded = bytes(b ^ 170 for b in raw_bytes)
        print(decoded.decode('utf-8', errors='replace'), end='')
    except Exception:
        pass

if __name__ == "__main__":
    if len(sys.argv) > 1:
        decode(sys.argv[1])
EOF

    useradd -m -s /bin/bash user || true

    # Setup SSH directory and authorized_keys with backdoor
    mkdir -p /home/user/.ssh
    cat << 'EOF' > /home/user/.ssh/authorized_keys
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC1 legit@server1
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC2 hacker@c2-server
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC3 legit@server2
EOF

    # Set insecure permissions as required by the initial state
    chmod -R 777 /home/user
