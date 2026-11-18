#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        imagemagick \
        fonts-dejavu-core \
        nginx \
        curl \
        jq \
        systemd

    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/.config/systemd/user
    cat << 'EOF' > /home/user/.config/systemd/user/profile-backend.service
[Unit]
Description=Profile Backend Service

[Service]
ExecStart=/usr/bin/python3 -m http.server 8084

[Install]
WantedBy=default.target
EOF

    mkdir -p /app
    convert -size 200x50 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 10,30 'Port: 8084'" /app/backend_port.png

    mkdir -p /home/user/deploy
    # Use base64 to avoid Apptainer templating engine parsing the curly braces
    echo "cHJveHlfcGFzcyBodHRwOi8vbG9jYWxob3N0Ont7QkFDS0VORF9QT1JUfX07" | base64 -d > /home/user/deploy/nginx.conf

    mkdir -p /home/user/incoming_profiles
    mkdir -p /home/user/public_profiles

    chown -R user:user /home/user
    chmod -R 777 /home/user
