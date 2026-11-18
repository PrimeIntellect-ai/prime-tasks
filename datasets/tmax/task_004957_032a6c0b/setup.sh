#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr gcc socat netcat-openbsd
    pip3 install pytest Pillow

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    python3 -c '
import os
import random
from PIL import Image, ImageDraw

# Generate image
img = Image.new("RGB", (800, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = "FINOPS ALERT POLICY\n1. Email must contain the exact header: \"X-FinOps-Token: 99A-XYZ\"\n2. The \"Total-Cost:\" value in the body must be strictly less than $8000.00."
d.text((10, 10), text, fill=(0, 0, 0))
img.save("/app/finops_policy.png")

# Generate corpus
clean_dir = "/app/corpus/clean"
evil_dir = "/app/corpus/evil"

for i in range(1, 51):
    with open(os.path.join(clean_dir, f"{i:02d}.eml"), "w") as f:
        cost = random.uniform(10, 7999)
        f.write(f"From: alert@finops.local\nTo: admin@finops.local\nSubject: Cost Alert\nX-FinOps-Token: 99A-XYZ\n\nTotal-Cost: ${cost:.2f}\n")

for i in range(1, 51):
    with open(os.path.join(evil_dir, f"{i:02d}.eml"), "w") as f:
        err_type = i % 3
        if err_type == 0:
            cost = random.uniform(10, 7999)
            f.write(f"From: alert@finops.local\nTo: admin@finops.local\nSubject: Cost Alert\n\nTotal-Cost: ${cost:.2f}\n")
        elif err_type == 1:
            cost = random.uniform(10, 7999)
            f.write(f"From: alert@finops.local\nTo: admin@finops.local\nSubject: Cost Alert\nX-FinOps-Token: BAD-TOKEN\n\nTotal-Cost: ${cost:.2f}\n")
        else:
            cost = random.uniform(8000, 15000)
            f.write(f"From: alert@finops.local\nTo: admin@finops.local\nSubject: Cost Alert\nX-FinOps-Token: 99A-XYZ\n\nTotal-Cost: ${cost:.2f}\n")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
