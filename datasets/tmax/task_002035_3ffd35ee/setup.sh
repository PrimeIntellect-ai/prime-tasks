#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/queue
    mkdir -p /home/user/homes

    chmod -R 777 /home/user
