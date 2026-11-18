#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest
    apt-get install -y git cargo netcat-openbsd

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
