#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl coreutils gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    RAW_SCRIPT='echo "Strict Policy Enforced: Target Delta"'
    B64_SCRIPT=$(echo -n "$RAW_SCRIPT" | base64 -w 0)

    KEY="102030405060708090a0b0c0d0e0f000102030405060708090a0b0c0d0e0f000"
    IV="000102030405060708090a0b0c0d0e0f"

    CIPHERTEXT=$(echo -n "$B64_SCRIPT" | openssl enc -aes-256-cbc -K "$KEY" -iv "$IV" -a | tr -d '\n')
    CHECKSUM=$(echo -n "$RAW_SCRIPT" | sha256sum | awk '{print $1}')

    cat <<EOF > /home/user/payload.dat
$KEY
$IV
$CIPHERTEXT
$CHECKSUM
EOF

    chmod -R 777 /home/user
