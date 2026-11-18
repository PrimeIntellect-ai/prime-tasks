#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg openssl fonts-dejavu-core
    pip3 install pytest

    # Create the user
    useradd -m -s /bin/bash user || true

    # Create directories
    mkdir -p /app
    mkdir -p /home/user/web_root/assets
    mkdir -p /home/user/web_root/includes

    # Generate the video with the passphrase
    ffmpeg -f lavfi -i color=c=black:s=640x480:d=10 -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='Passphrase\: X7k9P2mR5vL4qW1z':fontcolor=white:fontsize=24:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,3,5)'" -pix_fmt yuv420p /app/session_capture.mp4

    # Create web root files
    touch /home/user/web_root/index.html
    touch /home/user/web_root/assets/style.css
    touch /home/user/web_root/includes/config.php
    touch /home/user/web_root/includes/logger.php

    # Create and encrypt the access log
    cat << 'EOF' > /home/user/access.log
192.168.1.50 - - [10/Oct/2024:13:55:36 +0000] "GET /login HTTP/1.1" 200 1024
10.0.0.15 - - [10/Oct/2024:14:02:11 +0000] "GET /login?redirect=http://evil-phish.com/steal HTTP/1.1" 302 -
10.0.0.15 - alice_admin [10/Oct/2024:14:02:45 +0000] "POST /api/upload HTTP/1.1" 200 45
192.168.1.50 - - [10/Oct/2024:14:10:00 +0000] "GET /index.html HTTP/1.1" 200 2048
EOF

    openssl enc -aes-256-cbc -pbkdf2 -salt -in /home/user/access.log -out /home/user/encrypted_access.log.enc -pass pass:X7k9P2mR5vL4qW1z
    rm /home/user/access.log

    # Ensure /home/user is globally accessible but fix specific file permissions
    chmod -R 777 /home/user
    chmod 644 /home/user/web_root/index.html
    chmod 644 /home/user/web_root/assets/style.css
    chmod 666 /home/user/web_root/includes/config.php
    chmod 666 /home/user/web_root/includes/logger.php
