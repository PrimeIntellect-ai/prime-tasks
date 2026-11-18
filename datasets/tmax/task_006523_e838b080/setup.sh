#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create the user
    useradd -m -s /bin/bash user || true

    # Setup required before the agent begins
    mkdir -p /home/user/app_logs
    # Create a dummy file that is exactly 1,200,000 bytes to trigger the cleanup condition
    dd if=/dev/zero of=/home/user/app_logs/large_log.old bs=1000 count=1200
    # Create a small active log file
    echo "active log" > /home/user/app_logs/current.log

    # Set permissions
    chmod -R 777 /home/user
