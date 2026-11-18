#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Setup directories
    mkdir -p /home/user/artifacts/v1
    mkdir -p /home/user/artifacts/v2
    mkdir -p /home/user/artifacts/v3

    # Create standard binaries
    head -c 1024 /dev/urandom > /home/user/artifacts/v1/app.bin

    # v2 is a duplicate of v1
    cp /home/user/artifacts/v1/app.bin /home/user/artifacts/v2/app.bin

    # v3 is a new version
    head -c 1024 /dev/urandom > /home/user/artifacts/v3/app.bin

    # Ensure v3 is different from v1 (just in case urandom gave the same, highly unlikely)
    echo "diff" >> /home/user/artifacts/v3/app.bin

    # Create a valid symlink
    ln -s /home/user/artifacts/v3 /home/user/artifacts/latest

    # Create the loop
    ln -s /home/user/artifacts /home/user/artifacts/v3/loop_link

    # Set permissions
    chmod -R 777 /home/user
