#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssh-client tesseract-ocr
    pip3 install pytest pytesseract Pillow

    mkdir -p /app
    mkdir -p /home/user

    # Create the sticky note image using Python/Pillow to avoid ImageMagick policy issues
    python3 -c '
from PIL import Image, ImageDraw
img = Image.new("RGB", (300, 100), color="yellow")
d = ImageDraw.Draw(img)
d.text((10, 40), "ComplianceAdmin", fill="black")
img.save("/app/sticky_note.png")
'

    # Create the encrypted SSH key
    ssh-keygen -t rsa -b 2048 -N "ComplianceAdmin7" -f /app/admin_key_temp -q
    mv /app/admin_key_temp /app/admin_key.enc
    rm /app/admin_key_temp.pub

    # Create the target sshd_config
    cat << 'EOF' > /app/sshd_config.target
Port 22
PermitRootLogin yes
PasswordAuthentication yes
X11Forwarding no
AllowTcpForwarding no
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
