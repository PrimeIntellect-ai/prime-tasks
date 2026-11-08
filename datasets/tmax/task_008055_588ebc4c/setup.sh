#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest

    mkdir -p /home/user

    # Create secret file
    cat << 'EOF' > /home/user/secret.txt
User profile information:
Name: John Doe
Role: Administrator
Account: 1234-5678-9012-3456
API_KEY: 8f92j-29eu2-9283h
Account2: 9876-5432-1098-7654
EOF
    chmod 644 /home/user/secret.txt

    # Create vulnerable app
    cat << 'EOF' > /home/user/vulnerable_app.py
#!/usr/bin/env python3
import sys
import urllib.request
import json
import ssl

def main():
    if len(sys.argv) != 2:
        print("Usage: vulnerable_app.py <url>")
        sys.exit(1)

    url = sys.argv[1]

    # Ignore SSL errors for testing purposes
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    try:
        req = urllib.request.urlopen(url, context=ctx, timeout=5)
        data = json.loads(req.read().decode('utf-8'))

        file_path = data.get("file_to_read")
        if file_path:
            with open(file_path, 'r') as f:
                print(f.read())
        else:
            print("Error: 'file_to_read' not found in JSON payload.")
    except Exception as e:
        print(f"Failed to fetch or process data: {e}")

if __name__ == "__main__":
    main()
EOF
    chmod +x /home/user/vulnerable_app.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
