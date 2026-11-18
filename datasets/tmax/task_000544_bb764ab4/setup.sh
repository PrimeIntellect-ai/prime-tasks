#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app/services
    mkdir -p /home/user/shared_data
    mkdir -p /home/user/accounts
    mkdir -p /home/user/corpora/evil
    mkdir -p /home/user/corpora/clean

    cat << 'EOF' > /home/user/app/services/config.json
{
    "webhook_url": "http://127.0.0.1:9999/wrong",
    "api_host": "0.0.0.0"
}
EOF

    chmod -R 777 /home/user
