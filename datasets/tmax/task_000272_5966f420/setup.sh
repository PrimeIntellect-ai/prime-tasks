#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest websockets

    mkdir -p /app
    espeak -w /app/pipeline_instruction.wav "The target architecture is aarch 64. The authentication token is omega dash build dash 99."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
