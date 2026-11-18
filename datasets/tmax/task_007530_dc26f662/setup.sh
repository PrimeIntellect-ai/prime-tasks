#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest
    apt-get install -y rustc cargo openssl

    mkdir -p /home/user/evidence/bin
    mkdir -p /home/user/forensic_tool

    touch /home/user/evidence/bin/normal_script.sh
    touch /home/user/evidence/bin/backup_agent
    touch /home/user/evidence/bin/network_ping
    touch /home/user/evidence/bin/cleaner

    openssl req -x509 -newkey rsa:2048 -keyout /home/user/evidence/attacker.key -out /home/user/evidence/attacker.crt -days 365 -nodes -subj "/C=US/ST=State/L=City/O=Organization/CN=c2.evilcorp.local"

    cat << 'EOF' > /home/user/encode_payload.py
import binascii

plaintext = b"target_acquired:root_password=hunter2"
key = b"c2.evilcorp.local"

ciphertext = bytearray()
for i in range(len(plaintext)):
    ciphertext.append(plaintext[i] ^ key[i % len(key)])

hex_out = binascii.hexlify(ciphertext).decode('utf-8')
with open('/home/user/evidence/payload.enc', 'w') as f:
    f.write(hex_out)
EOF
    python3 /home/user/encode_payload.py
    rm /home/user/encode_payload.py /home/user/evidence/attacker.key

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user

    chmod -R 777 /home/user
    chmod 4755 /home/user/evidence/bin/backup_agent
    chmod 4755 /home/user/evidence/bin/network_ping
