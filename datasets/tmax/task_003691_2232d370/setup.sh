#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --no-cache-dir pytest cryptography

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/server.log
[2023-10-25 10:00:01] [INFO] Server starting up...
[2023-10-25 10:00:02] [DEBUG] Initializing crypto modules.
[2023-10-25 10:00:03] [ERROR] KeyManager failed to bind to HSM. Falling back to local key. Leak: AES_KEY=7a5c32b98e4f1a6d0781c24e9b3a5f8d
[2023-10-25 10:01:15] [INFO] User login attempt: admin
[2023-10-25 10:01:16] [DEBUG] Generating Content Security Policy headers.
[2023-10-25 10:01:16] [DEBUG] Active CSP nonce generated: Z1xP9qA4vN8mB2wE
[2023-10-25 10:02:45] [INFO] Redirecting user to dashboard.
EOF

    chmod -R 777 /home/user
