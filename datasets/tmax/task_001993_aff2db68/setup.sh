#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest pyinstaller

    mkdir -p /app

    # Generate the voicemail.wav file
    espeak -w /app/voicemail.wav "Hi, this is Dave from security. The emergency token override key is eight three nine two zero one. Keep it safe."

    # Create the oracle source code
    cat << 'EOF' > /tmp/oracle.py
#!/usr/bin/env python3
import sys
import re
import binascii
import itertools

def main():
    if len(sys.argv) < 2:
        return
    cookie_string = sys.argv[1]

    match = re.search(r'redirect_token=([a-fA-F0-9]+)', cookie_string)
    if not match:
        print("ERROR: Missing token")
        return

    hex_token = match.group(1)
    if len(hex_token) % 2 != 0:
        print("ERROR: Invalid hex")
        return

    try:
        encrypted_bytes = binascii.unhexlify(hex_token)
    except binascii.Error:
        print("ERROR: Invalid hex")
        return

    key = b"839201"
    decrypted_bytes = bytes([b ^ k for b, k in zip(encrypted_bytes, itertools.cycle(key))])

    try:
        url = decrypted_bytes.decode('ascii')
    except UnicodeDecodeError:
        print("DENY: Open Redirect")
        return

    if url.startswith("https://trusted.corp.local/"):
        print(f"ALLOW: {url}")
    else:
        print("DENY: Open Redirect")

if __name__ == "__main__":
    main()
EOF

    # Compile the oracle binary
    pyinstaller --onefile /tmp/oracle.py --distpath /app -n token_oracle
    chmod +x /app/token_oracle

    # Cleanup
    rm -rf /tmp/oracle.py build token_oracle.spec

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
