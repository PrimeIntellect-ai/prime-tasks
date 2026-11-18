#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create the user and home directory
    useradd -m -s /bin/bash user || true

    # Make sure /home/user is fully accessible
    chmod -R 777 /home/user
