#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg
pip3 install pytest

mkdir -p /app
mkdir -p /home/user/archive

# Generate a 60-second video with motion at specific intervals
# Static portions are black, motion portions use testsrc
ffmpeg -y -f lavfi -i color=c=black:s=320x240:r=30 -f lavfi -i testsrc=s=320x240:r=30 \
-filter_complex "[0:v][1:v]blend=all_expr='if(between(T,12,18)+between(T,35,42)+between(T,50,55), B, A)'" \
-c:v libx264 -preset ultrafast -t 60 /app/surveillance.mp4

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user /app
