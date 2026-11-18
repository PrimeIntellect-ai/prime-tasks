#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak-ng cargo rustc
    pip3 install pytest requests

    mkdir -p /app
    espeak-ng -w /app/auth_token.wav "The authentication token is blue sunrise"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
