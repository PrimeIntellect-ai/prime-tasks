#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/generate_docs.py
import time
import sys

def main():
    # Generates 2500 blocks of 5 lines each = 12500 lines total
    for i in range(1, 2501):
        sys.stdout.write(f"# Document Entry {i}\n")
        sys.stdout.write(f"This is the first detail line for entry {i}.\n")
        sys.stdout.write(f"This is the second detail line for entry {i}.\n")
        sys.stdout.write(f"This is the third detail line for entry {i}.\n")
        sys.stdout.write(f"This is the conclusion for entry {i}.\n")
        sys.stdout.flush()
        # Sleep briefly to simulate streaming/racing
        time.sleep(0.0005)

if __name__ == '__main__':
    main()
EOF

    chmod +x /home/user/generate_docs.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
