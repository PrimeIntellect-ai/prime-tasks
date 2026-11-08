#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr fonts-liberation
    pip3 install pytest pytesseract Pillow numpy

    mkdir -p /app

    # Create the oracle processor
    cat << 'EOF' > /app/oracle_processor.py
import sys
import json
import re

matrix = [[3, -1], [2, 4]]

def process():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            decoded_line = re.sub(r'\\u([0-9a-fA-F]{4})', lambda m: chr(int(m.group(1), 16)), line)
            data = json.loads(decoded_line)
            if 'coordinates' in data and 'x' in data['coordinates'] and 'y' in data['coordinates']:
                x = data['coordinates']['x']
                y = data['coordinates']['y']
                if isinstance(x, (int, float)) and isinstance(y, (int, float)):
                    nx = matrix[0][0] * x + matrix[0][1] * y
                    ny = matrix[1][0] * x + matrix[1][1] * y
                    out = {"original_x": x, "original_y": y, "transformed_x": nx, "transformed_y": ny}
                    print(json.dumps(out))
        except Exception:
            pass

if __name__ == '__main__':
    process()
EOF

    # Generate the image with the transformation matrix
    cat << 'EOF' > /app/generate_image.py
from PIL import Image, ImageDraw, ImageFont
img = Image.new('RGB', (200, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf", 30)
except:
    font = ImageFont.load_default()
d.text((10, 10), " 3 -1\n 2  4", fill=(0, 0, 0), font=font)
img.save('/app/transformation_matrix.png')
EOF
    python3 /app/generate_image.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
