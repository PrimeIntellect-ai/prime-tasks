#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required packages for the task
    apt-get install -y qemu-system-x86 nginx g++ openssl curl tar

    # Create user
    useradd -m -s /bin/bash user || true

    # Create directories required by the task description (optional but good practice to ensure they can be created by the agent or pre-exist if needed, but agent should create them. I will just ensure /home/user is clean and ready)

    chmod -R 777 /home/user
