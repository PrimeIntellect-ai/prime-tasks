#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    echo "storage_available_kb=4194304" > /home/user/device_storage.txt

    chmod -R 777 /home/user
