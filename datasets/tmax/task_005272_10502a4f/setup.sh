#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest
apt-get install -y ffmpeg g++ make nginx logrotate openssl curl gawk

mkdir -p /app
# Generate a video with 5 distinct red flashes
ffmpeg -y -f lavfi -i "color=c=green:s=320x240:d=10" \
       -vf "drawbox=x=0:y=0:w=320:h=240:color=red:t=fill:enable='between(t,1,1.5)+between(t,3,3.5)+between(t,5,5.5)+between(t,7,7.5)+between(t,9,9.5)'" \
       -c:v libx264 -pix_fmt yuv420p /app/server_status.mp4

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
