#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ espeak curl
    pip3 install pytest

    mkdir -p /app
    espeak -w /app/memo.wav "The backup token is Echo 4 0 4."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
