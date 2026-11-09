#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg golang sqlite3 curl
    pip3 install pytest

    # Create app directory
    mkdir -p /app

    # Create SRT file with graph data
    cat << 'EOF' > /tmp/subs.srt
1
00:00:00,000 --> 00:00:01,000
A,B,5

2
00:00:01,000 --> 00:00:02,000
B,D,10

3
00:00:02,000 --> 00:00:03,000
A,C,8

4
00:00:03,000 --> 00:00:04,000
C,D,3

5
00:00:04,000 --> 00:00:05,000
B,C,2
EOF

    # Generate video with embedded subtitle track
    ffmpeg -f lavfi -i color=c=black:s=320x240:d=5 -i /tmp/subs.srt -c:v libx264 -c:s mov_text /app/network_topology.mp4
    rm /tmp/subs.srt

    # Set permissions for /app
    chmod -R 777 /app

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
