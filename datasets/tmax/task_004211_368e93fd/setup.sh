#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip socat jq curl espeak-ng
    pip3 install pytest

    mkdir -p /app
    espeak-ng -w /app/voicemail.wav "The updated policy ID is seven seven delta foxtrot."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
