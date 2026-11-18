#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Setup directories
    mkdir -p /home/user/data/logs
    mkdir -p /home/user/data/archive

    # Create placeholder
    echo "FILE OFFLINE" > /home/user/data/offline_placeholder.txt

    # Create dummy log files (approx 2.5 MB each)
    dd if=/dev/urandom of=/home/user/data/logs/app_alpha.log bs=1024 count=2500 status=none
    dd if=/dev/urandom of=/home/user/data/logs/app_beta.log bs=1024 count=2500 status=none
    dd if=/dev/urandom of=/home/user/data/logs/app_gamma.log bs=1024 count=2500 status=none

    # Set ownership and permissions
    chown -R user:user /home/user/data
    chmod -R 777 /home/user
