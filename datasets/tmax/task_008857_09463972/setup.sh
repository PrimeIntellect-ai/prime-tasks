#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        g++ \
        build-essential

    pip3 install --no-cache-dir pytest jupyter pandas matplotlib

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
