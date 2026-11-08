#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make espeak ffmpeg curl
    pip3 install pytest

    mkdir -p /app
    espeak -w /app/experiment_dictation.wav "Methionine, Alanine, Serine, Glycine, Tyrosine."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
