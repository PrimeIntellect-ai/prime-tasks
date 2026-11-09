#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc espeak
    pip3 install pytest

    # Create /app directory
    mkdir -p /app

    # Generate audio file for the directive
    espeak -w /app/directive.wav "golden eagle"

    # Create user
    useradd -m -s /bin/bash user || true

    # Create server.conf
    cat << 'EOF' > /home/user/server.conf
port=8080
extract_dir=/home/user/artifacts
EOF

    # Set permissions
    chmod -R 777 /home/user
    chmod -R 777 /app
