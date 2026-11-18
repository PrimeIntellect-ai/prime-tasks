#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip parallel socat netcat-openbsd gawk bc espeak
pip3 install pytest

# Install CPU-only PyTorch to avoid massive downloads and timeouts, then install whisper
pip3 install torch --index-url https://download.pytorch.org/whl/cpu
pip3 install openai-whisper

mkdir -p /app/data
espeak -w /app/data/experiment_audio.wav "The target concentrations are 39, 63, 78, 86, and 92."

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
