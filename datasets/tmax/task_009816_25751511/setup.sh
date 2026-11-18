#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/ids_logic.py
import sys

def calculate_hash(data):
    # Weak linear hash function
    return sum(ord(c) * (i + 1) for i, c in enumerate(data)) % 65536

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 ids_logic.py <file>")
        sys.exit(1)

    try:
        with open(sys.argv[1], 'r') as f:
            content = f.read()
    except FileNotFoundError:
        print("STATUS: FILE NOT FOUND")
        sys.exit(1)

    h = calculate_hash(content)

    # Whitelist check overrides all other rules
    if h == 42069:
        print("STATUS: WHITELISTED")
    else:
        # Sensitive data check
        if "4532-" in content or "EXFIL" in content:
            print("STATUS: MALWARE DETECTED")
        else:
            print("STATUS: UNKNOWN")
EOF

    chmod -R 777 /home/user
