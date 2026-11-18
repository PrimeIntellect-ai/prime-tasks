#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required system packages
    apt-get install -y rustc cargo cron logrotate

    # Create the user
    useradd -m -s /bin/bash user || true

    # Ensure permissions
    chmod -R 777 /home/user
