#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/analyzer
    mkdir -p /home/user/proxy

    chmod -R 777 /home/user
