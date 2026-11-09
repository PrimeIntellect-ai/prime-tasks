#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git jq
    pip3 install pytest

    # Create the user
    useradd -m -s /bin/bash user || true

    # Ensure correct permissions
    chmod -R 777 /home/user
