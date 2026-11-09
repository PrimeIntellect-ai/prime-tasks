#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest

    # Generate the video file with 3 different test sources to create visual shifts at frames 10 and 20
    mkdir -p /app
    ffmpeg -y -f lavfi -i testsrc=d=10:s=320x240:r=1 \
           -f lavfi -i testsrc2=d=10:s=320x240:r=1 \
           -f lavfi -i rgbtestsrc=d=10:s=320x240:r=1 \
           -filter_complex "[0:v][1:v][2:v]concat=n=3:v=1:a=0[outv]" \
           -map "[outv]" -r 1 -c:v libx264 /app/experiment_record.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
