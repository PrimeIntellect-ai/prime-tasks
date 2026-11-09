#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required system packages
    apt-get install -y git socat procps curl

    # Create the user
    useradd -m -s /bin/bash user || true

    # Set permissions
    chmod -R 777 /home/user
