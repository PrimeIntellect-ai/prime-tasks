#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git cron
    pip3 install --default-timeout=100 pytest

    useradd -m -s /bin/bash user || true

    chmod -R 777 /home/user
