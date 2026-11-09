#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git gcc libc6-dev netcat-openbsd gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Configure git for the user to avoid warnings during the task
    su - user -c "git config --global init.defaultBranch main"
    su - user -c "git config --global user.name 'Edge User'"
    su - user -c "git config --global user.email 'edge@example.com'"

    chmod -R 777 /home/user
