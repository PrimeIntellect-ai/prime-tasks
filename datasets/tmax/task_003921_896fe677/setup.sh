#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required packages for the task and tests
    apt-get install -y socat netcat-openbsd iproute2 procps

    # Create the user
    useradd -m -s /bin/bash user || true

    # Ensure home directory permissions
    chmod -R 777 /home/user
