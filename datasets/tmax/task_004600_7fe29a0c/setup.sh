#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg netcat-openbsd socat curl jq
    pip3 install pytest

    # Create directories
    mkdir -p /app
    mkdir -p /home/user/app

    # Generate dummy surveillance video
    ffmpeg -f lavfi -i testsrc=duration=10:size=320x240:rate=30 -c:v libx264 -pix_fmt yuv420p /app/surveillance.mp4

    # Create buggy video_server.sh
    cat << 'EOF' > /home/user/app/video_server.sh
#!/bin/bash
# Buggy video server daemon
LOGS=()

while true; do
    # Memory leak: appending to array infinitely
    LOGS+=("Request received at $(date +%s%N)")

    # Listen for connections
    nc -l -p 8080 -c '
        read request
        # ... process request
    '
done
EOF
    chmod +x /home/user/app/video_server.sh

    # Create user
    useradd -m -s /bin/bash user || true

    # Set permissions
    chmod -R 777 /home/user
    chmod -R 777 /app
