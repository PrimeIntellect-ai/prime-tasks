#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install --default-timeout=100 pytest Pillow

    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Generate the image with the firewall spec
    cat << 'EOF' > /app/generate_image.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (300, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), "SSH_PORT=9922\nEMAIL_PORT=2525", fill=(0, 0, 0))
img.save('/app/fw_spec.png')
EOF
    python3 /app/generate_image.py
    rm /app/generate_image.py

    # Create sample evil logs
    echo "sshd[1234]: Authentication refused: bad ownership or modes for directory /root" > /app/corpora/evil/log1.txt
    echo "sshd[1235]: Authentication refused: bad ownership or modes for file /home/user/.ssh/authorized_keys" > /app/corpora/evil/log2.txt

    # Create sample clean logs
    echo "sshd[1236]: Accepted publickey for root from 192.168.1.1 port 54321 ssh2" > /app/corpora/clean/log1.txt
    echo "sshd[1237]: Failed password for invalid user admin from 10.0.0.5 port 2222 ssh2" > /app/corpora/clean/log2.txt
    echo "sshd[1238]: Disconnected from authenticating user root 192.168.1.2 port 33333" > /app/corpora/clean/log3.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
