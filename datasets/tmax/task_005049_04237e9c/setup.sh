#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr fonts-liberation
    pip3 install pytest Pillow

    mkdir -p /app

    cat << 'EOF' > /tmp/make_image.py
from PIL import Image, ImageDraw, ImageFont

text = """State S1 S2 S3 S4
S1 0.1 0.4 0.2 0.3
S2 0.5 0.0 0.3 0.2
S3 0.2 0.2 0.4 0.2
S4 0.1 0.3 0.3 0.3"""

img = Image.new('RGB', (800, 400), color='white')
d = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf", 40)
except:
    font = ImageFont.load_default()

d.text((20, 20), text, fill='black', font=font)
img.save('/app/transition_matrix.png')
EOF
    python3 /tmp/make_image.py

    cat << 'EOF' > /app/oracle.py
#!/usr/bin/env python3
import sys

matrix = {
    'S1': [0.1, 0.4, 0.2, 0.3],
    'S2': [0.5, 0.0, 0.3, 0.2],
    'S3': [0.2, 0.2, 0.4, 0.2],
    'S4': [0.1, 0.3, 0.3, 0.3]
}
states = ['S1', 'S2', 'S3', 'S4']

if len(sys.argv) < 2:
    sys.exit(1)

curr = sys.argv[1]
path = [curr]

for r_str in sys.argv[2:]:
    r = float(r_str)
    probs = matrix[curr]
    cum = 0.0
    next_state = states[-1]
    for i, p in enumerate(probs):
        cum += p
        if r < cum:
            next_state = states[i]
            break
    path.append(next_state)
    curr = next_state

print(" ".join(path))
EOF
    chmod +x /app/oracle.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
