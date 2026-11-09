#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg rustc cargo build-essential curl
pip3 install pytest

mkdir -p /app
ffmpeg -f lavfi -i testsrc=duration=10:size=640x480:rate=30 -c:v libx264 /app/video.mp4

cat << 'EOF' > /app/telemetry.csv
timestamp,value,notes
1,100,"All good"
2,100,"Warning: bad road
needs fixing"
3,100,"Clear"
4,150,"Speeding up"
5,150,"Cruising"
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
