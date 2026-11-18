#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest Pillow

    # Install required packages for the task
    apt-get install -y tesseract-ocr libssl-dev libseccomp-dev gcc libc-dev

    # Create the application directory
    mkdir -p /app

    # Generate the admin note image with the partial key
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (200, 50), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 15), 'BASE: W4X9', fill=(0, 0, 0))
img.save('/app/admin_note.png')
"

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
