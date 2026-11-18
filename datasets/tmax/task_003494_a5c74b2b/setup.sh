#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip binutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup.py
import os
import random
import string

# Generate fake memory dump
with open('/home/user/service_dump.bin', 'wb') as f:
    # write some random binary garbage
    f.write(os.urandom(1024 * 50))

    # write the valid logs interspersed
    for _ in range(100):
        valid_user = ''.join(random.choices(string.ascii_lowercase, k=8))
        f.write(f"USER_LOGIN: {valid_user};\n".encode('utf-8'))
        f.write(os.urandom(128))

    # write the leaked strings
    for _ in range(5000):
        f.write(b"USER_LOGIN: admin_no_semi_4920\n")
        f.write(os.urandom(16))

    f.write(os.urandom(1024 * 50))

# Generate parser.py
with open('/home/user/parser.py', 'w') as f:
    f.write("""leaked_records = []

def process_log(log_line):
    # A buggy parser that attempts to extract username
    if "USER_LOGIN:" in log_line:
        # Expected format: USER_LOGIN: <username>;
        parts = log_line.split("USER_LOGIN:")
        if len(parts) > 1:
            username_part = parts[1].strip()
            if ";" not in username_part:
                # Edge case: missing semicolon.
                # Buffers indefinitely expecting a continuation
                leaked_records.append(username_part)
                return False

            username = username_part.split(";")[0]
            return True
    return False
""")
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    chmod -R 777 /home/user
