#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        ffmpeg \
        zbar-tools \
        netcat-openbsd \
        jq \
        bc \
        qrencode

    pip3 install pytest

    # Create directories
    mkdir -p /app/frames
    mkdir -p /home/user

    # Generate QR codes
    qrencode -s 10 -o /app/frames/frame01.png '{"path": "/home/user/project/src/main.c", "expr": "100 + 25"}'
    qrencode -s 10 -o /app/frames/frame02.png '{"path": "/home/user/project/src/auth.sh", "expr": "8 * 2"}'
    qrencode -s 10 -o /app/frames/frame03.png '{"path": "/home/user/project/docs/readme.md", "expr": "20 / 2"}'

    # Create video
    ffmpeg -framerate 1 -i /app/frames/frame%02d.png -c:v libx264 -r 30 -pix_fmt yuv420p /app/recovery.mp4
    rm -rf /app/frames

    # Create legacy order file
    cat << 'EOF' > /home/user/legacy_order.txt
/home/user/project/src/main.c
/home/user/project/docs/readme.md
/home/user/project/src/auth.sh
EOF

    # Create user
    useradd -m -s /bin/bash user || true

    # Set permissions
    chmod -R 777 /home/user
    chmod -R 777 /app
