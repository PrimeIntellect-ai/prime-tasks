#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ tar
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    touch /home/user/.bashrc

    chmod -R 777 /home/user
