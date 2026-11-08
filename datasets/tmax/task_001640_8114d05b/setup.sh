#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required packages
    apt-get install -y ffmpeg gcc make locales tzdata

    # Generate required locale
    locale-gen ja_JP.UTF-8
    update-locale

    # Create dummy video file (testing environment will mount the real one)
    mkdir -p /app
    touch /app/edge_feed.mp4

    # Create user
    useradd -m -s /bin/bash user || true

    # Set permissions
    chmod -R 777 /home/user
