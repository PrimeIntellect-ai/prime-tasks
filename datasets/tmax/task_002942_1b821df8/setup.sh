#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-opencv
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user/scripts

    # Generate video and encrypted token
    cat << 'EOF' > /tmp/setup.py
import cv2
import numpy as np
import os

key_hex = "5ca83f91b20d44e71a8f"
key_bytes = bytes.fromhex(key_hex)
bits = []
for b in key_bytes:
    for i in range(7, -1, -1):
        bits.append((b >> i) & 1)

fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/evidence.mp4', fourcc, 10.0, (100, 100))

for bit in bits:
    color = 255 if bit == 1 else 0
    frame = np.full((100, 100, 3), color, dtype=np.uint8)
    out.write(frame)

out.release()

plaintext = b"VULNERABLE_TARGET=backup_sys.sh\n"
ciphertext = bytearray()
for i in range(len(plaintext)):
    ciphertext.append(plaintext[i] ^ key_bytes[i % len(key_bytes)])

with open('/home/user/encrypted_token.bin', 'wb') as f:
    f.write(ciphertext)
EOF
    python3 /tmp/setup.py
    rm /tmp/setup.py

    # Create scripts
    cat << 'EOF' > /home/user/scripts/backup_sys.sh
#!/bin/bash
# Runs as root via sudo
tar -czf /var/backups/archive.tar.gz $1
EOF

    cat << 'EOF' > /home/user/scripts/cleanup.sh
#!/bin/bash
rm -rf /tmp/*
EOF

    cat << 'EOF' > /home/user/scripts/monitor.sh
#!/bin/bash
top -b -n 1
EOF

    chmod +x /home/user/scripts/*.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
