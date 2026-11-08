#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Initialize bare git repository
    mkdir -p /home/user/monitor.git
    cd /home/user/monitor.git && git init --bare

    # Use PID 1 (which is always running in the container) as the target process
    echo 1 > /home/user/target.pid

    chmod -R 777 /home/user
