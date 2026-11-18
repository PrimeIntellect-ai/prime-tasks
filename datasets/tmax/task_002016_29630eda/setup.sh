#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg

    # Install Python dependencies, using CPU-only PyTorch to avoid massive downloads and timeouts
    pip3 install pytest
    pip3 install torch torchvision --index-url https://download.pytorch.org/whl/cpu
    pip3 install pandas numpy Pillow

    # Create the required video file for the task
    mkdir -p /app
    ffmpeg -y -f lavfi -i testsrc=duration=30:size=640x480:rate=30 /app/data.mp4

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
