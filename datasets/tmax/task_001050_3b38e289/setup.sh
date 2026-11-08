#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest Pillow

    # Install required packages for the task
    apt-get install -y tesseract-ocr g++ libssl-dev fonts-dejavu-core

    # Create app directory
    mkdir -p /app

    # Generate the policy image using Python and Pillow
    python3 -c '
from PIL import Image, ImageDraw, ImageFont
import os

img = Image.new("RGB", (800, 400), color="white")
d = ImageDraw.Draw(img)

try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 24)
except IOError:
    font = ImageFont.load_default()

text = "REQUIRED_COOKIE: AuthToken=DevSecOps_XYZ99\nREDACT_WORD: TITAN_PROJECT\nAES_KEY: 5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d"
d.text((50, 50), text, fill="black", font=font)

img.save("/app/policy_config.png")
'

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
