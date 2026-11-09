#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        openssh-server \
        socat \
        netcat-openbsd \
        curl \
        tesseract-ocr \
        ffmpeg \
        libsm6 \
        libxext6

    pip3 install pytest Pillow numpy imageio imageio-ffmpeg

    mkdir -p /app
    mkdir -p /run/sshd

    # Generate the incident_record.mp4 video
    python3 -c "
import numpy as np
import imageio
from PIL import Image, ImageDraw

frames = []
for i in range(400):
    img = Image.new('RGB', (1200, 200), color=(0, 0, 0))
    d = ImageDraw.Draw(img)
    if 100 <= i <= 150:
        d.text((10, 50), 'Attacker Key: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIObXy6kR3/58P9zB1A/N+Qz5e7J5h2W6X8Y9rVp+aE9q attacker@evil.local', fill=(255, 255, 255))
    if 300 <= i <= 380:
        d.text((10, 100), 'ELF Payload Offset 0x4010: http://malicious.corp.attacker.local/auth_bypass', fill=(255, 255, 255))
    frames.append(np.array(img))

imageio.mimwrite('/app/incident_record.mp4', frames, fps=30, macro_block_size=1)
"

    # Also append the strings directly to the end of the file in case the agent uses `strings` instead of OCR
    echo "Attacker Key: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIObXy6kR3/58P9zB1A/N+Qz5e7J5h2W6X8Y9rVp+aE9q attacker@evil.local" >> /app/incident_record.mp4
    echo "ELF Payload Offset 0x4010: http://malicious.corp.attacker.local/auth_bypass" >> /app/incident_record.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
