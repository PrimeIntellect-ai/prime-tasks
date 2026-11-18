#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg sudo
    pip3 install pytest

    mkdir -p /app/backup_metadata/
    cat << 'EOF' > /app/backup_metadata/daily_manifest.log
[Record Start]
ID: 101
Priority: Low
Start_Sec: 0
End_Sec: 2
[Record End]

[Record Start]
ID: 102
Priority: Critical
Start_Sec: 3
End_Sec: 7
[Record End]
EOF

    # Generate a 10-second 30fps 1080p video
    ffmpeg -f lavfi -i testsrc=duration=10:size=1920x1080:rate=30 -c:v libx264 -pix_fmt yuv420p /app/camera_feed.mp4

    useradd -m -s /bin/bash user || true
    echo "user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
    chmod -R 777 /home/user
