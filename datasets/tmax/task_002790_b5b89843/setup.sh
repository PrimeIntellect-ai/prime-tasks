#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create directories for the task
    mkdir -p /home/user/compat/proto
    mkdir -p /home/user/compat/server
    mkdir -p /home/user/compat/tests

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
