#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip expect
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/legacy_net_setup.py
#!/usr/bin/env python3
import sys
import time
import base64

def main():
    try:
        sys.stdout.write("Enter cluster name: ")
        sys.stdout.flush()
        cluster = input().strip()

        sys.stdout.write("Enter base port (1024-65535): ")
        sys.stdout.flush()
        port = input().strip()

        sys.stdout.write("Enable IPv6? (y/n): ")
        sys.stdout.flush()
        ipv6 = input().strip()

        print("\nValidating inputs...")
        time.sleep(0.5)
        print("Allocating network namespaces...")

        raw_token = f"{cluster}:{port}:{ipv6}".encode('utf-8')
        token = base64.b64encode(raw_token).decode('utf-8')

        print(f"SUCCESS: Node configured. token={token} endpoint=127.0.0.1:{port}")
    except EOFError:
        print("\nERROR: Unexpected EOF")
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF

    chmod +x /home/user/legacy_net_setup.py
    chmod -R 777 /home/user
