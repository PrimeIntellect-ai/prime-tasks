#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        fonts-dejavu-core

    pip3 install pytest Pillow pandas

    mkdir -p /app/specs
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    cat << 'EOF' > /tmp/setup_data.py
import os
import random
from PIL import Image, ImageDraw, ImageFont

# Generate Image
img = Image.new('RGB', (800, 300), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = """DATA FILTRATION RULES:
1. The 'temperature' column must not exceed 45.5 (<= 45.5)
2. The 'pressure' column must be strictly positive (> 0.0)
3. The 'status' column must not contain the exact string 'ERROR'"""

try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 20)
except:
    font = ImageFont.load_default()

d.text((20, 20), text, fill=(0, 0, 0), font=font)
img.save('/app/specs/validation_rules.png')

# Generate CSVs
headers = "timestamp,temperature,pressure,status\n"

for i in range(20):
    # Clean
    with open(f"/app/corpus/clean/clean_{i}.csv", "w") as f:
        f.write(headers)
        for j in range(5):
            temp = random.uniform(20.0, 45.5)
            press = random.uniform(0.1, 10.0)
            status = random.choice(["OK", "WARNING", "IDLE"])
            f.write(f"2023-01-01T00:00:0{j},{temp:.2f},{press:.2f},{status}\n")

    # Evil
    with open(f"/app/corpus/evil/evil_{i}.csv", "w") as f:
        f.write(headers)
        for j in range(5):
            if j == 2:
                # Inject error
                error_type = random.choice(["temp", "press", "status", "nan"])
                if error_type == "temp":
                    temp = random.uniform(45.6, 60.0)
                    press = random.uniform(0.1, 10.0)
                    status = "OK"
                elif error_type == "press":
                    temp = random.uniform(20.0, 45.5)
                    press = random.uniform(-10.0, 0.0)
                    status = "OK"
                elif error_type == "status":
                    temp = random.uniform(20.0, 45.5)
                    press = random.uniform(0.1, 10.0)
                    status = "ERROR"
                else:
                    temp = ""
                    press = random.uniform(0.1, 10.0)
                    status = "OK"
                f.write(f"2023-01-01T00:00:0{j},{temp},{press:.2f},{status}\n")
            else:
                temp = random.uniform(20.0, 45.5)
                press = random.uniform(0.1, 10.0)
                status = random.choice(["OK", "WARNING", "IDLE"])
                f.write(f"2023-01-01T00:00:0{j},{temp:.2f},{press:.2f},{status}\n")

EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
