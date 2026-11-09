#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc inotify-tools gzip coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create initial directories and files
    mkdir -p /home/user/docs
    touch /home/user/manifest.txt

    chmod -R 777 /home/user
