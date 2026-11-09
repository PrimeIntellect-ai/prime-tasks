#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr fonts-liberation
    pip3 install pytest Pillow

    mkdir -p /app/data

    python3 -c '
import os
import random
import math
from PIL import Image, ImageDraw, ImageFont

os.makedirs("/app/data", exist_ok=True)
with open("/app/data/traffic.csv", "w") as f:
    f.write("id,clicks,impressions,emb_x,emb_y,emb_z\n")
    random.seed(42)
    for i in range(1, 10001):
        x = random.uniform(-1, 1)
        y = random.uniform(-1, 1)
        z = random.uniform(-1, 1)
        norm = math.sqrt(x*x + y*y + z*z)
        x, y, z = x/norm, y/norm, z/norm

        imp = str(random.randint(50, 500))
        clk = str(random.randint(0, int(imp)))

        if random.random() < 0.05:
            imp = ""
        if random.random() < 0.05:
            clk = ""

        f.write(f"{i},{clk},{imp},{x:.4f},{y:.4f},{z:.4f}\n")

font = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf", 20)
img = Image.new("RGB", (400, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = "Bayesian Prior specs:\nAlpha: 12\nBeta: 45\n\nTarget Embedding Threshold:\nSimilarity_Threshold: 0.82"
d.text((10,10), text, fill=(0,0,0), font=font)
img.save("/app/prior_specs.png")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
