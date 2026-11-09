#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create directories mentioned in the task
    mkdir -p /home/user/src /home/user/bin /home/user/wrong_logs /home/user/data

    chmod -R 777 /home/user
