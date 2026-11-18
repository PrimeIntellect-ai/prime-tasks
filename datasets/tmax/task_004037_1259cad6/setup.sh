#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv build-essential curl binutils
    pip3 install pytest requests hypothesis flask

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
