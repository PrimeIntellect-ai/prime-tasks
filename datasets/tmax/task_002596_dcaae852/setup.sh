#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils grep sed
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Fix permissions
    chmod -R 777 /home/user
