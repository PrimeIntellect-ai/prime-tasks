#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/incident_042
    mkdir -p /home/user/legacy_app/logs
    mkdir -p /home/user/legacy_app/scripts

    touch /home/user/legacy_app/README.md
    touch /home/user/legacy_app/logs/access.log
    touch /home/user/legacy_app/scripts/backup.sh
    touch /home/user/legacy_app/scripts/clean.sh
    touch /home/user/legacy_app/config.json

    cat << 'EOF' > /home/user/incident_042/crypto_module.py
def lcg_encrypt(plaintext: bytes, seed: int, a: int, c: int) -> bytes:
    """
    Encrypts data using a simple LCG stream cipher.
    X_{n+1} = (a * X_n + c) mod 256
    C_i = P_i ^ X_i
    """
    ciphertext = bytearray()
    x = seed
    for byte in plaintext:
        ciphertext.append(byte ^ x)
        x = (a * x + c) % 256
    return bytes(ciphertext)
EOF

    echo -n "4f2a14dd273347a2709e3bb8f328f522f281ce1c7a82b0e7a270ca8c56bf3eb65c69d80d22c918c575ad44547dfb24c88a53e9447701cdb0e5bc5cd6e98ebf" > /home/user/incident_042/suspicious_payload.hex

    chmod -R 777 /home/user
    chmod 644 /home/user/legacy_app/README.md
    chmod 644 /home/user/legacy_app/logs/access.log
    chmod 777 /home/user/legacy_app/scripts/backup.sh
    chmod 755 /home/user/legacy_app/scripts/clean.sh
    chmod 666 /home/user/legacy_app/config.json
