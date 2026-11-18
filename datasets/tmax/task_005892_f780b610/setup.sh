#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install necessary tools for the task
    apt-get install -y gcc openssh-client coreutils

    # Create user
    useradd -m -s /bin/bash user || true

    # Make home directory accessible
    chmod -R 777 /home/user
