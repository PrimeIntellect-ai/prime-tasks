#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget curl
    pip3 install pytest

    # Download and extract passlib 1.7.4
    mkdir -p /app
    cd /app
    wget -qO passlib.tar.gz https://files.pythonhosted.org/packages/source/p/passlib/passlib-1.7.4.tar.gz
    tar -xzf passlib.tar.gz
    rm passlib.tar.gz

    # Inject artificial delay into md5_crypt.py
    sed -i '/def _calc_checksum/a \    import time; time.sleep(0.05)' /app/passlib-1.7.4/passlib/handlers/md5_crypt.py

    # Install the modified passlib into the system environment
    cd /app/passlib-1.7.4
    pip3 install -e .

    # Create user and home directory
    useradd -m -s /bin/bash user || true

    # Create legacy_hashes.txt
    cat << 'EOF' > /home/user/legacy_hashes.txt
$1$rK3a9V1p$M8a5.h4g.K3p9v7Z4g2H10
$1$aB2cD3eF$x8Y9z0A1b2C3d4E5f6G7h.
EOF

    # Create audit.py
    cat << 'EOF' > /home/user/audit.py
import sys
import argparse
import json
from passlib.hash import md5_crypt

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--passwords', required=True, help='Comma separated passwords')
    args = parser.parse_args()

    passwords = args.passwords.split(',')

    with open('/home/user/legacy_hashes.txt', 'r') as f:
        hashes = [line.strip() for line in f if line.strip()]

    cracked = {}
    for h in hashes:
        for p in passwords:
            if md5_crypt.verify(p, h):
                cracked[h] = p
                break

    with open('/home/user/cracked.json', 'w') as f:
        json.dump(cracked, f, indent=4)

if __name__ == '__main__':
    main()
EOF

    # Ensure correct permissions
    chmod -R 777 /home/user
