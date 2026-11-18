#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip logrotate binutils
    pip3 install pytest pyinstaller

    # Create the python script for the hasher
    cat << 'EOF' > /tmp/hasher.py
import sys
import hashlib
data = sys.stdin.read().encode('utf-8')
print(hashlib.md5(data).hexdigest().upper(), end='')
EOF

    # Compile it to a binary using pyinstaller
    cd /tmp
    pyinstaller --onefile hasher.py

    # Move to the required location
    mkdir -p /app
    cp dist/hasher /app/config_hasher
    chmod +x /app/config_hasher

    # Cleanup
    rm -rf /tmp/hasher* /tmp/build /tmp/dist

    # Create the user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
