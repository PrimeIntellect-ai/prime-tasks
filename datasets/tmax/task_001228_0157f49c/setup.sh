#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest pillow scikit-learn numpy flask fastapi uvicorn pytesseract requests

    mkdir -p /app

    # Generate the experiment_config.png image
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 100), color='white')
d = ImageDraw.Draw(img)
d.text((10, 10), 'EXPERIMENT_SEED: 8128', fill='black')
d.text((10, 50), 'TARGET_VARIANCE: 0.90', fill='black')
img.save('/app/experiment_config.png')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
