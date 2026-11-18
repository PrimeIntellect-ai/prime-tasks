#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install additional required packages
    apt-get install -y nginx acl cron curl

    # Create user
    useradd -m -s /bin/bash user || true

    # Ensure permissions are open for the agent
    chmod -R 777 /home/user
