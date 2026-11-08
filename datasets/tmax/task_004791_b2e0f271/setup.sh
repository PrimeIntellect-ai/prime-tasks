#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
pip3 install pytest Pillow

mkdir -p /app

# Generate the math spec image using Python and Pillow
cat << 'EOF' > /tmp/gen_img.py
from PIL import Image, ImageDraw
text = """Expanding Window Scaler

For an input array X of length N, the output array Y is defined as:
For i from 1 to N:
  mu_i = mean(X[1...i])
  sigma_i = population_std_dev(X[1...i])   // use ddof=0
  Y_i = (X[i] - mu_i) / (sigma_i + 0.01)

Round all final Y_i to 4 decimal places."""

img = Image.new('RGB', (800, 400), color = (255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,10), text, fill=(0,0,0))
img.save('/app/math_spec.png')
EOF
python3 /tmp/gen_img.py

# Create the oracle script
cat << 'EOF' > /app/oracle_scaler.py
#!/usr/bin/env python3
import sys
import json
import math

def process():
    input_data = sys.stdin.read()
    if not input_data.strip():
        return

    try:
        X = json.loads(input_data)
    except:
        sys.exit(1)

    Y = []
    for i in range(len(X)):
        window = X[:i+1]
        mu = sum(window) / len(window)
        variance = sum((x - mu) ** 2 for x in window) / len(window)
        sigma = math.sqrt(variance)

        y_val = (X[i] - mu) / (sigma + 0.01)
        Y.append(round(y_val, 4))

    print(json.dumps(Y))

if __name__ == "__main__":
    process()
EOF
chmod +x /app/oracle_scaler.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
