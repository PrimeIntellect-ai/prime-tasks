#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/deployments
    mkdir -p /home/user/.config/systemd/user

    cat << 'EOF' > /home/user/targets.conf
app_alpha:root
app_beta:daemon
app_gamma:fakeuser99
app_delta:nobody
app_epsilon:nonexistent_admin
EOF

    chmod -R 777 /home/user
