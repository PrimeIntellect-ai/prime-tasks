#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg espeak
    pip3 install pytest

    # Install CPU-only PyTorch to save build time and size
    pip3 install torch --index-url https://download.pytorch.org/whl/cpu
    pip3 install openai-whisper

    mkdir -p /app

    # Generate the audio file
    espeak -w /app/deployment_weights.wav "The new deployment requires the following load balancer weights. Route one has a weight of fifteen. Route two has a weight of twenty five. Route three has a weight of sixty."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
