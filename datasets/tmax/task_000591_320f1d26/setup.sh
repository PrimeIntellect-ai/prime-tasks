#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr fonts-liberation
pip3 install pytest Pillow

mkdir -p /app
mkdir -p /home/user/raw_logs

# Generate the policy image
python3 -c '
from PIL import Image, ImageDraw, ImageFont
img = Image.new("RGB", (800, 400), color="white")
d = ImageDraw.Draw(img)
font = ImageFont.truetype("/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf", 24)
text = "LOG_DIR=/home/user/raw_logs\nARCHIVE_DIR=/home/user/archive\nCHUNK_SIZE=10000000"
d.text((10,10), text, fill="black", font=font)
img.save("/app/policy.png")
'

# Generate the 50MB dummy log file
python3 -c '
line = "{\"level\": \"INFO\", \"message\": \"System check OK\", \"timestamp\": \"2023-10-01T12:00:00Z\"}\n"
with open("/home/user/raw_logs/system.log", "w") as f:
    for _ in range(600000):
        f.write(line)
'

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
