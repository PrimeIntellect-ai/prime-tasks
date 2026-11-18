#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    if [ ! -f /home/user/.bashrc ]; then
        echo "# .bashrc" > /home/user/.bashrc
    fi

    chmod -R 777 /home/user
