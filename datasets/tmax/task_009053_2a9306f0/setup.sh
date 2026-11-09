#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/legacy_auth.log
[INFO] System startup initiated.
[DEBUG] AUTH_PAYLOAD=YWxiZXJ0OjgxZGM5YmRiNTJkMDRkYzIwMDM2ZGJkODMxM2VkMDU1
[WARN] Unrecognized command received.
[DEBUG] AUTH_PAYLOAD=aW52YWxpZF9wYXlsb2FkX2hlcmVfd2l0aG91dF9oYXNo
[INFO] Connection closed.
[DEBUG] AUTH_PAYLOAD=Ym9iOmZhMjQ2ZDAyNjJjMzkyNTYxN2IwYzcyYmIyMGVlYjFk
[ERROR] Database timeout.
[DEBUG] AUTH_PAYLOAD=c2lzdGVtYV9hZG1pbjphMWQwYzZlODNmMDI3MzI3ZDg0NjEwNjNmNGFjNThhNg==
[DEBUG] AUTH_PAYLOAD=ZGVjb2Rlc190b19nYXJiYWdl
EOF

    chmod -R 777 /home/user
