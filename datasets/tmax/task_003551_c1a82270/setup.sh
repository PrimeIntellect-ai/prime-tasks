#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install packages needed for the task
    apt-get install -y gcc libgsl-dev coreutils

    # Create user
    useradd -m -s /bin/bash user || true

    # Create dataset
    seq 1.0 1.0 100.0 > /home/user/data.txt

    # Set permissions
    chmod -R 777 /home/user
