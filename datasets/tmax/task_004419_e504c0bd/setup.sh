#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required system packages
    apt-get install -y ffmpeg cargo rustc curl wget

    # Create /app directory
    mkdir -p /app

    # Create mock fstab
    cat << 'EOF' > /app/fstab.mock
/dev/sda1 /boot ext4 defaults 0 2
/dev/sda2 / xfs defaults 0 1
tmpfs /run tmpfs defaults 0 0
EOF

    # Generate a dummy test video (5 seconds)
    ffmpeg -f lavfi -i testsrc=duration=5:size=320x240:rate=30 -c:v libx264 /app/test_video.mp4

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
