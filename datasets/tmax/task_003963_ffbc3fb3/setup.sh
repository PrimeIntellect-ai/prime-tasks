#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc git
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Ensure git config for user to avoid commit errors
    su - user -c "git config --global user.email 'user@example.com'"
    su - user -c "git config --global user.name 'User'"

    chmod -R 777 /home/user
