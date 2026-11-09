#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget tar
    pip3 install pytest

    # Create app directory
    mkdir -p /app
    cd /app

    # Download and extract watchdog 3.0.0
    wget https://files.pythonhosted.org/packages/source/w/watchdog/watchdog-3.0.0.tar.gz
    tar -xzf watchdog-3.0.0.tar.gz
    rm watchdog-3.0.0.tar.gz

    # Introduce deliberate bug in events.py
    sed -i 's/import os/import brokensystem_module/' /app/watchdog-3.0.0/src/watchdog/events.py

    # Setup directories
    mkdir -p /home/user/datasets/incoming/

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
