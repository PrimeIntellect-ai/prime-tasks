#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg nginx
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /app/corpus/clean /app/corpus/evil

    cat << 'EOF' > /app/corpus/clean/config1.json
{"service": "app", "mount_path": "/var/lib/data"}
EOF

    cat << 'EOF' > /app/corpus/clean/config2.json
{"service": "cache", "mount_path": "/tmp/cache"}
EOF

    cat << 'EOF' > /app/corpus/evil/mal1.json
{"service": "hack", "mount_path": "/var/lib/data/../../etc"}
EOF

    cat << 'EOF' > /app/corpus/evil/mal2.json
{"service": "steal", "mount_path": "../root/.ssh"}
EOF

    # Generate a video with exactly 144 frames
    ffmpeg -f lavfi -i color=c=black:s=320x240:r=24 -frames:v 144 -c:v libx264 /app/security_cam.mp4

    chmod -R 777 /home/user
