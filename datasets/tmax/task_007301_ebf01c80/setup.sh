#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    if [ ! -f /home/user/.bashrc ]; then
        cp /etc/skel/.bashrc /home/user/.bashrc || touch /home/user/.bashrc
    fi

    chmod -R 777 /home/user
