#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg qrencode git openssh-server openssh-client zbar-tools curl
    pip3 install pytest

    mkdir -p /app

    # Generate QR code image
    qrencode -o /tmp/qr.png '{"git_port": 9418, "http_port": 8080, "tunnel_port": 8081}'

    # Create video from QR code image
    ffmpeg -loop 1 -i /tmp/qr.png -c:v libx264 -t 5 -pix_fmt yuv420p -vf scale=320:320 /app/k8s_ops.mp4

    # Clean up
    rm /tmp/qr.png

    useradd -m -s /bin/bash user || true

    # Setup sshd for the task
    mkdir -p /run/sshd

    chmod -R 777 /home/user
