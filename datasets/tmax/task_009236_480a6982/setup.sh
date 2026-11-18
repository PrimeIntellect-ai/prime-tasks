#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang logrotate
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create workspace directory
    mkdir -p /home/user/workspace

    chmod -R 777 /home/user
