#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app
    mkdir -p /home/user/app/subdir

    echo "super_secret_key_12345" > /home/user/secret.txt

    # Create dummy vulnerable and safe files
    touch /home/user/app/safe_file.txt
    touch /home/user/app/suid_bin
    touch /home/user/app/world_writable.log
    touch /home/user/app/subdir/another_suid

    # Create dummy python server
    cat << 'EOF' > /home/user/app/server.py
#!/usr/bin/env python3
import os
print("Running secure server")
print("AUTH_TOKEN:", os.environ.get("AUTH_TOKEN"))
EOF

    # Apply general permissions
    chmod -R 777 /home/user

    # Apply specific security permissions required for the task tests
    chmod 4755 /home/user/app/suid_bin
    chmod 4755 /home/user/app/subdir/another_suid
    chmod 666 /home/user/app/world_writable.log
