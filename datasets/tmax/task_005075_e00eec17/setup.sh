#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make time
    pip3 install pytest

    mkdir -p /home/user/workspace

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
