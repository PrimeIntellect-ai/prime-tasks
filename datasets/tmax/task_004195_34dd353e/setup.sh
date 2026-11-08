#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick
    pip3 install pytest

    mkdir -p /app

    # Generate the legacy policy image
    convert -size 800x400 xc:white -fill black -pointsize 24 -annotate +50+50 "AUDIT POLICY MEMO\nIntegrity Algorithm: HMAC-SHA256\nSecret Salt: SecureAuditTrail2024!\nData format: username:role" /app/legacy_policy.png

    # Create the oracle script
    cat << 'EOF' > /app/oracle_mac
#!/usr/bin/env python3
import sys
import hmac
import hashlib

def main():
    if len(sys.argv) != 3:
        sys.exit(1)
    username = sys.argv[1]
    role = sys.argv[2]
    secret = b"SecureAuditTrail2024!"
    data = f"{username}:{role}".encode('utf-8')
    mac = hmac.new(secret, data, hashlib.sha256).hexdigest()
    print(mac, end="")

if __name__ == "__main__":
    main()
EOF
    chmod +x /app/oracle_mac

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
