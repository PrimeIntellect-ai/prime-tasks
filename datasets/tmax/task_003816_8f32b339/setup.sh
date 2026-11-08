#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go espeak curl
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/servers.txt
# Primary cluster
192.168.1.10
192.168.1.11

# Secondary cluster
10.0.0.5
EOF

    espeak -w /app/auth_message.wav "The emergency deployment authorization passcode is 839201."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
