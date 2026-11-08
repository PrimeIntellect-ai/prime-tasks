#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git iproute2 tzdata
    pip3 install pytest

    # Create the bare git repository
    mkdir -p /home/user/monitor.git
    cd /home/user/monitor.git
    git init --bare

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
