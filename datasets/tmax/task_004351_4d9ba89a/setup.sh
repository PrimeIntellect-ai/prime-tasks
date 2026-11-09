#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc python3-pil
    pip3 install pytest

    mkdir -p /app
    mkdir -p /opt/verifier/corpora/evil/
    mkdir -p /opt/verifier/corpora/clean/

    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (600, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 50), 'Valid points condition: val_A^2 + val_B^2 <= 625', fill=(0, 0, 0))
img.save('/app/formula.png')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
