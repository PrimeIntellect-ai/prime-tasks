#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssh-server
    pip3 install pytest cryptography

    # Create vendored package directory structure
    mkdir -p /app/vendored/py-auditor-1.2.0/py_auditor

    # Create hasher.py with perturbed code
    cat << 'EOF' > /app/vendored/py-auditor-1.2.0/py_auditor/hasher.py
import hashlib
def get_file_hash(filepath):
    with open(filepath, 'rb') as f:
        return hashlib.md5(f.read()).hexdigest()
EOF

    # Create __init__.py
    touch /app/vendored/py-auditor-1.2.0/py_auditor/__init__.py

    # Create setup.py
    cat << 'EOF' > /app/vendored/py-auditor-1.2.0/setup.py
from setuptools import setup, find_packages

setup(
    name="py-auditor",
    version="1.2.0",
    packages=find_packages(),
)
EOF

    # Generate SSH keypair
    ssh-keygen -t rsa -b 2048 -f /app/auditor_id_rsa -N ""

    # Generate AES key
    head -c 32 /dev/urandom > /app/aes_key.bin

    # Ensure /var/run/sshd exists
    mkdir -p /var/run/sshd

    # Create user
    useradd -m -s /bin/bash user || true

    # Adjust permissions
    chmod -R 777 /app
    chmod -R 777 /home/user
