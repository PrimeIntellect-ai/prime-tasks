#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install packages required for the task
    apt-get install -y golang-go curl bash coreutils

    # Create the user
    useradd -m -s /bin/bash user || true

    # Fix permissions
    chmod -R 777 /home/user
