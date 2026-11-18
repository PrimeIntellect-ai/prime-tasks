#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest pillow

    # Configure git globally so commits work without errors
    git config --system user.email "test@example.com"
    git config --system user.name "Test User"
    git config --system init.defaultBranch master

    mkdir -p /app

    # Generate the diagram.png using Python and Pillow
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), 'Log File: /home/user/deploy_metrics.log', fill=(0, 0, 0))
d.text((10, 50), 'Service Name: backend-api', fill=(0, 0, 0))
img.save('/app/diagram.png')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
