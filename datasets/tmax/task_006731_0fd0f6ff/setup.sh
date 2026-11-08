#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import hashlib

def setup_env():
    # Secret values
    password = b"melon"
    salt = b"x8z9k1m2"

    # Calculate the SHA256 hash of password + salt
    hasher = hashlib.sha256()
    hasher.update(password + salt)
    target_hash = hasher.digest()

    # Create the binary file with dummy ELF headers and garbage data
    binary_path = "/home/user/auth_server"

    with open(binary_path, "wb") as f:
        # Dummy ELF header
        f.write(b"\x7fELF\x02\x01\x01\x00" + b"\x00"*8)
        f.write(b"x" * 128) # Garbage

        # Inject SALT
        f.write(b"SALT_HDR")
        f.write(salt)

        f.write(b"y" * 256) # More garbage

        # Inject HASH
        f.write(b"HASH_HDR")
        f.write(target_hash)

        f.write(b"z" * 64) # End garbage

    os.chmod(binary_path, 0o755)

if __name__ == "__main__":
    setup_env()
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
