#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr jq python3-pil fonts-liberation
pip3 install pytest

python3 -c '
import os
import json
from PIL import Image, ImageDraw, ImageFont

os.makedirs("/app/corpus/clean", exist_ok=True)
os.makedirs("/app/corpus/evil", exist_ok=True)

img = Image.new("RGB", (1200, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf", 24)
except IOError:
    font = ImageFont.load_default()

text = "Perceptron Anomaly Detector: weight_x = 2.5, weight_y = -1.5, bias = 0.5.\nFlag as Anomaly if (weight_x * x) + (weight_y * y) + bias >= 5.0"
d.text((10, 50), text, fill=(0, 0, 0), font=font)
img.save("/app/architecture.png")

clean_data = [{"x": 1.0, "y": 2.0}, {"x": 0.0, "y": 0.0}, {"x": -1.0, "y": -1.0}]
for i, data in enumerate(clean_data):
    with open(f"/app/corpus/clean/clean_{i}.json", "w") as f:
        json.dump(data, f)

evil_data = [{"x": 4.0, "y": 1.0}, {"x": 5.0, "y": 0.0}, {"x": 10.0, "y": 10.0}]
for i, data in enumerate(evil_data):
    with open(f"/app/corpus/evil/evil_{i}.json", "w") as f:
        json.dump(data, f)
'

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
