#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user

    # Generate the audio file
    espeak -w /app/incident_report.wav "The anomaly was detected on server cluster delta prime."

    # Create the server inventory encoded in UTF-16LE
    cat << 'EOF' > /tmp/inventory.txt
alpha-node-01
beta-node-02
cluster-delta-prime
cluster-gamma-sub
epsilon-main-hub
EOF

    iconv -f UTF-8 -t UTF-16LE /tmp/inventory.txt > /home/user/server_inventory.bin
    rm /tmp/inventory.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
