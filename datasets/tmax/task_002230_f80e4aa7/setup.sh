#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg nginx acl curl cargo
    pip3 install --default-timeout=100 pytest requests numpy scipy

    mkdir -p /app
    ffmpeg -f lavfi -i "sine=frequency=1000:duration=60" -ac 1 -ar 44100 /app/input.wav

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
