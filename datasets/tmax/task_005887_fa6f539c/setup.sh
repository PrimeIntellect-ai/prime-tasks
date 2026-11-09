#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create the user
    useradd -m -s /bin/bash user || true

    # Setup initial state
    mkdir -p /home/user/state
    echo '[{"id": 100, "ts": 1690000000, "val": "INIT"}]' > /home/user/state/master.json

    # Ensure permissions
    chmod -R 777 /home/user
