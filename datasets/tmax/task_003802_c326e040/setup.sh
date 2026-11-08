#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg fonts-dejavu-core
pip3 install pytest

mkdir -p /app
echo "admin' UNION SELECT null, 'root', null--" > /tmp/payload.txt
ffmpeg -y -f lavfi -i color=c=black:s=640x480:d=10 -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf:text='Disassembly output...':fontcolor=green:fontsize=24:x=10:y=10, drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf:textfile=/tmp/payload.txt:fontcolor=green:fontsize=24:x=10:y=50:enable='between(t,7,8)'" -c:v libx264 /app/c2_terminal_screencast.mp4
chmod 644 /app/c2_terminal_screencast.mp4

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
