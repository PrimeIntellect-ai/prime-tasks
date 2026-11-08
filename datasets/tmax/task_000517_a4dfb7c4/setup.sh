#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        ffmpeg \
        g++ \
        make \
        libopencv-dev

    pip3 install pytest

    # Create the fixture video
    mkdir -p /app
    ffmpeg -f lavfi -i testsrc=duration=10:size=320x240:rate=10 \
      -vf "drawbox=x=0:y=0:w=320:h=240:color=black@1.0:t=fill:enable='between(n,25,35)'" \
      -pix_fmt yuv420p /app/sensor_feed.mp4

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
