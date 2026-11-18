#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git cargo rustc logrotate iproute2
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Configure git so commits can be made during testing
    cat << 'EOF' > /home/user/.gitconfig
[user]
    name = Test User
    email = test@example.com
[init]
    defaultBranch = master
EOF
    chown user:user /home/user/.gitconfig

    chmod -R 777 /home/user
