#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg cron
    pip3 install pytest

    mkdir -p /app

    # Create dummy subtitle file
    cat << 'EOF' > /tmp/dummy.srt
1
00:00:01,000 --> 00:00:04,000
Hello world.

2
00:00:05,000 --> 00:00:08,000
This is a test.
EOF

    # Create video with embedded SRT subtitle (using MKV container renamed to MP4 to ensure SRT support)
    ffmpeg -f lavfi -i color=c=black:s=320x240:d=10 -i /tmp/dummy.srt -c:v libx264 -c:s srt /app/presentation.mkv
    mv /app/presentation.mkv /app/presentation.mp4

    # Create metadata CSV
    cat << 'EOF' > /app/metadata.csv
timestamp,event_type,user_comment
2023-10-15T14:25:01Z,click,nice
2023-10-15T14:59:59Z,view,
2023-10-15T15:05:00Z,click,great
2023-10-16T09:12:00Z,view,hello
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
