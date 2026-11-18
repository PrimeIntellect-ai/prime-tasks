#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak curl
    pip3 install pytest

    mkdir -p /app
    espeak -w /app/manifest_instruction.wav "Use image redis tag six point zero and set replicas to four."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
