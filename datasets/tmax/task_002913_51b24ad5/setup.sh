#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip inotify-tools jq
    pip3 install pytest watchdog

    useradd -m -s /bin/bash user || true

    chmod -R 777 /home/user
