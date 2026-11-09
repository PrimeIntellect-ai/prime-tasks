#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest

    mkdir -p /app

    # Generate a ~5MB sample video
    ffmpeg -f lavfi -i testsrc=duration=20:size=1280x720:rate=30 -c:v libx264 -b:v 2M /app/artifact_feed.mp4

    # Create the configuration file
    cat << 'EOF' > /app/repo_layout.conf
BASE_DIR=/home/user/repository
PRIMARY_LOCATION=releases/v2.0/main_artifact.mp4
HARD_LINKS=stable/latest.mp4,promoted/v2.mp4
SYM_LINKS=experimental/beta.mp4
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
