#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        golang \
        gcc \
        libc6-dev \
        curl \
        iproute2

    pip3 install pytest

    # Create directories
    mkdir -p /home/user/waf

    # Create user
    useradd -m -s /bin/bash user || true

    # Set permissions
    chmod -R 777 /home/user
