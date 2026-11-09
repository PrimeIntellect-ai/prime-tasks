#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv redis-server curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app

    chmod -R 777 /home/user
