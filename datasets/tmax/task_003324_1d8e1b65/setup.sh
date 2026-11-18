#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/known_pairs.csv
PlaintextByte,CiphertextByte
65,32
66,43
67,54
100,161
EOF

    python3 -c '
a = 11
b = 85
plaintext = b"AUDIT_START: System initialized securely."
ciphertext = bytes([(a * p + b) % 256 for p in plaintext])
with open("/home/user/historical_traffic.enc", "wb") as f:
    f.write(ciphertext)
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
