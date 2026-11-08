#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /tmp/evidence
    cat << 'EOF' > /tmp/evidence/login_validator.py
import hashlib

def check_pin(pin):
    salt = "X9_p3n_T3st"
    # Append salt to the pin and hash
    h = hashlib.sha256((pin + salt).encode()).hexdigest()
    return h
EOF

    cd /tmp/evidence
    python3 -m py_compile login_validator.py
    mv __pycache__/login_validator.*.pyc login_validator.pyc
    python3 -c "import hashlib; print(hashlib.sha256('7392X9_p3n_T3st'.encode()).hexdigest(), end='')" > target_hash.txt

    zip -r /home/user/evidence.zip login_validator.pyc target_hash.txt
    sha256sum /home/user/evidence.zip | awk '{print $1}' > /home/user/evidence.zip.sha256

    rm -rf /tmp/evidence

    chmod -R 777 /home/user
