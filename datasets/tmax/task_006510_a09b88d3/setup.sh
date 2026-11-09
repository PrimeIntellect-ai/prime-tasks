#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssh-client
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/.ssh

    cat << 'EOF' > /home/user/token_generator.py
import random
import time

def generate_all_tokens():
    ts = 1715000000
    random.seed(ts)

    guest_token = f"guest-{random.randint(10000000, 99999999)}"
    admin_token = f"admin-{random.randint(10000000, 99999999)}"

    with open('/home/user/auth.log', 'w') as f:
        f.write(f"[{ts}] Batch token generation started.\n")
        f.write(f"[{ts}] Issued token: {guest_token}\n")
        f.write(f"[{ts}] Issued token for admin, but it is kept secret.\n")

if __name__ == "__main__":
    generate_all_tokens()
EOF

    python3 /home/user/token_generator.py

    chmod -R 777 /home/user
    chmod 0700 /home/user/.ssh
