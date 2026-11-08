#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg gcc
pip3 install pytest

# Create a sample "surveillance" video that is mostly static
mkdir -p /app
ffmpeg -f lavfi -i color=c=blue:s=320x240:d=8 -f lavfi -i color=c=red:s=320x240:d=2 -filter_complex "[0:v][1:v]concat=n=2:v=1:a=0[outv]" -map "[outv]" -c:v libx264 /app/surveillance.mp4

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
