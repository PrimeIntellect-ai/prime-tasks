#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ netcat-openbsd coreutils
    pip3 install pytest

    # Create the user
    useradd -m -s /bin/bash user || true

    # Ensure permissions
    chmod -R 777 /home/user
