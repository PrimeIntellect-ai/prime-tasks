#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev gcc
    pip3 install pytest packaging

    mkdir -p /home/user/libs/bin
    mkdir -p /home/user/project

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
