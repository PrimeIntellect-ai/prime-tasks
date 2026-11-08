#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y --no-install-recommends python3 python3-pip tesseract-ocr imagemagick bc gawk
    pip3 install pytest numpy Pillow

    mkdir -p /app

    # Create data.csv
    python3 -c "
import numpy as np
np.random.seed(42)
data = np.random.randn(1000, 3) * [10, 5, 2] + [50, -20, 5]
np.savetxt('/app/data.csv', data, delimiter=',', fmt='%.4f')
"

    # Create weights.png using Python to avoid imagemagick font issues or use convert if available
    python3 -c "
from PIL import Image, ImageDraw, ImageFont
img = Image.new('RGB', (300, 50), color='white')
d = ImageDraw.Draw(img)
d.text((10, 10), '0.35 0.80 -0.25', fill='black')
img.save('/app/weights.png')
"

    # Fallback to convert if needed, but Pillow is safer and doesn't need fonts installed
    # convert -background white -fill black -pointsize 24 label:"0.35 0.80 -0.25" /app/weights.png || true

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
