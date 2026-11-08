#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg golang-go curl zip unzip tar
    pip3 install pytest

    mkdir -p /app

    # Generate a 5-second dummy video
    ffmpeg -f lavfi -i testsrc=duration=5:size=320x240:rate=10 -c:v mpeg4 /app/demo.mp4

    # Generate bundle.tar.gz
    mkdir -p /tmp/setup && cd /tmp/setup
    echo -n "LEGACY_PROJECT_IDENTIFIER_9942" > project_data.txt
    zip inner.zip project_data.txt
    tar -czf /app/bundle.tar.gz inner.zip
    rm -rf /tmp/setup

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
