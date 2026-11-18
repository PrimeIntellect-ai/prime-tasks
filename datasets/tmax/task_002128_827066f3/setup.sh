#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg jq gawk netcat-openbsd socat
pip3 install pytest

mkdir -p /app
cat << 'EOF' > /tmp/telemetry.srt
1
00:00:01,000 --> 00:00:02,000
{"ts": 1700000000, "t": 20.0, "h": 45.5, "status": "flying\u002Xhigh"}

2
00:00:02,000 --> 00:00:03,000
{"ts": 1700000001, "t": 22.5, "h": null, "status": "steady\u002Xstate"}

3
00:00:03,000 --> 00:00:04,000
{"ts": 1700000002, "t": -5.0, "h": 80.0, "status": "descending"}
EOF

ffmpeg -f lavfi -i color=c=black:s=320x240:d=5 -i /tmp/telemetry.srt -c:v libx264 -c:s mov_text -map 0:v -map 1:s /app/telemetry.mp4

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
