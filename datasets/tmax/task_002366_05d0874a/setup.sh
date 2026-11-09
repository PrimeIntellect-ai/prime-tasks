#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gcc make curl libmicrohttpd-dev binutils
    pip3 install pytest Pillow numpy

    mkdir -p /app
    ffmpeg -f lavfi -i testsrc=duration=2:size=320x240:rate=30 -pix_fmt yuv420p /app/thermal_experiment.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
