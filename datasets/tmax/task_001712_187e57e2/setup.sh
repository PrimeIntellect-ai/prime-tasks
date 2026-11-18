#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip tar
    pip3 install pytest

    mkdir -p /tmp/setup
    cd /tmp/setup

    cat << 'EOF' > api.txt
# API Documentation
The API is completely RESTful and returns JSON.
EOF

    cat << 'EOF' > intro.txt
# Introduction
Welcome to the super awesome project.
EOF

    cat << 'EOF' > setup.txt
# Setup Instructions
1. Run `make install`
2. Run `make test`
EOF

    zip project.zip api.txt intro.txt setup.txt

    mkdir -p /home/user
    tar -czvf /home/user/docs.tar.gz project.zip

    cd /
    rm -rf /tmp/setup

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
