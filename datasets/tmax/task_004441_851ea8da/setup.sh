#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl xxd
    pip3 install pytest pycryptodome

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/auth_verifier.py
#!/usr/bin/env python3
import sys
import base64
import json
from Crypto.Cipher import AES

# Vulnerability: Hardcoded key
KEY = b"RedTeamEvasion99"

def verify(token_path):
    try:
        with open(token_path, 'r') as f:
            token = f.read().strip()

        cipher = AES.new(KEY, AES.MODE_ECB)
        # Decrypts without unpadding to avoid padding errors for this scenario
        decrypted_bytes = cipher.decrypt(base64.b64decode(token))
        decrypted_str = decrypted_bytes.strip(b'\x00').decode('utf-8')

        data = json.loads(decrypted_str)

        if data.get("role") == "admin" and data.get("user") == "system":
            print("Authentication Bypass Successful")
            with open("/home/user/success.log", "w") as f:
                f.write("Bypassed")
        else:
            print("Authentication Failed: Insufficient privileges")
    except Exception as e:
        print(f"Error processing token: {e}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: verify.py <token_file>")
        sys.exit(1)
    verify(sys.argv[1])
EOF

    chmod 0755 /home/user/auth_verifier.py
    chmod -R 777 /home/user
