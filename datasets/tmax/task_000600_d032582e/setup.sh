#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg tesseract-ocr sqlite3 curl socat netcat-openbsd
pip3 install pytest

mkdir -p /app
# Generate a video with text appearing over time
ffmpeg -y -f lavfi -i color=c=white:s=800x600:d=6 \
-vf " \
drawtext=text='Tx101 ACQUIRE ResA':fontcolor=black:fontsize=40:x=50:y=50:enable='between(t,0,6)', \
drawtext=text='Tx102 ACQUIRE ResB':fontcolor=black:fontsize=40:x=50:y=100:enable='between(t,1,6)', \
drawtext=text='Tx103 ACQUIRE ResC':fontcolor=black:fontsize=40:x=50:y=150:enable='between(t,2,6)', \
drawtext=text='Tx104 ACQUIRE ResD':fontcolor=black:fontsize=40:x=50:y=200:enable='between(t,2,6)', \
drawtext=text='Tx101 WAIT ResB':fontcolor=black:fontsize=40:x=50:y=250:enable='between(t,3,6)', \
drawtext=text='Tx102 WAIT ResC':fontcolor=black:fontsize=40:x=50:y=300:enable='between(t,4,6)', \
drawtext=text='Tx103 WAIT ResA':fontcolor=black:fontsize=40:x=50:y=350:enable='between(t,5,6)', \
drawtext=text='Tx105 WAIT ResC':fontcolor=black:fontsize=40:x=50:y=400:enable='between(t,5,6)', \
drawtext=text='Tx106 WAIT ResC':fontcolor=black:fontsize=40:x=50:y=450:enable='between(t,5,6)' \
" -c:v libx264 -pix_fmt yuv420p /app/db_monitor.mp4

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
