#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required packages
    apt-get install -y cargo rustc git netcat-openbsd cron build-essential

    # Create the user
    useradd -m -s /bin/bash user || true

    # Ensure cron is ready to be used (cron service might need to be started by the test or agent, but we install it)
    chmod -R 777 /home/user
