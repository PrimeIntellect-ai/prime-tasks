#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required packages for the task
    apt-get install -y g++ haproxy supervisor netcat-openbsd

    # Create directories
    mkdir -p /home/user/mail_router
    mkdir -p /home/user/mail_spool

    # Create user
    useradd -m -s /bin/bash user || true

    # Set permissions
    chmod -R 777 /home/user
