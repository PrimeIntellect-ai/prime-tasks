#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required packages for the task
    apt-get install -y haproxy gcc make curl iproute2

    # Create user
    useradd -m -s /bin/bash user || true

    # Create required directories
    mkdir -p /home/user/manifests
    mkdir -p /home/user/mail_spool

    # Set permissions
    chmod -R 777 /home/user
