#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the new_volume directory just in case, though the agent's script should handle it
    mkdir -p /home/user/new_volume

    chmod -R 777 /home/user
