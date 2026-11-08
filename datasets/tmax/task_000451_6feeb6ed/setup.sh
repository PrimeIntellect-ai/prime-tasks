#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest watchdog pyelftools

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/spool
    mkdir -p /home/user/archive

    chmod -R 777 /home/user
