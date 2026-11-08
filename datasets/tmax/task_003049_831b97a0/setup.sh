#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl ffmpeg espeak rustc cargo
    pip3 install pytest

    mkdir -p /app
    espeak -w /app/artifact_091.wav "The experiment was a complete success and the pipeline is stable."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
