#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required packages
    apt-get install -y g++ socat netcat-openbsd

    # Create user
    useradd -m -s /bin/bash user || true

    # Create configuration file
    cat << 'EOF' > /home/user/services.conf
127.0.0.1:9005
127.0.0.1:9006
EOF

    # Set permissions
    chmod -R 777 /home/user
