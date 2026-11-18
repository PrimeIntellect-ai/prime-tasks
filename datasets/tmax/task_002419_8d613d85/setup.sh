#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr fonts-dejavu-core
    pip3 install pytest pillow

    mkdir -p /app/corpora/clean /app/corpora/evil

    # Generate the image
    python3 -c '
from PIL import Image, ImageDraw, ImageFont
img = Image.new("RGB", (1600, 400), color=(255, 255, 255))
d = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 24)
except:
    font = ImageFont.load_default()
text = """PIPELINE SPECIFICATION
1. Columns to extract: tx_id, timestamp, amount, description.
2. Gap-filling: If the timestamp is missing, calculate it by adding exactly 60 seconds to the timestamp of the immediately preceding row. Format is ISO8601 (e.g. 2023-01-01T10:00:00Z).
3. Suspicious rules: A description is suspicious if it contains the exact uppercase word '\''TEST'\'', the exact uppercase word '\''DEMO'\'', or any sequence of 4 or more consecutive digits."""
d.text((20, 20), text, fill=(0, 0, 0), font=font)
img.save("/app/schema_spec.png")
'

    # Generate transactions.csv
    python3 -c '
import csv
import random
from datetime import datetime, timedelta

with open("/app/transactions.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["tx_id", "timestamp", "user_id", "amount", "description", "notes"])
    dt = datetime(2023, 1, 1, 10, 0, 0)
    for i in range(10000):
        ts = "" if i % 10 == 0 and i > 0 else dt.strftime("%Y-%m-%dT%H:%M:%SZ")
        writer.writerow([f"tx_{i}", ts, f"user_{i%100}", round(random.uniform(1, 1000), 2), f"desc {i}", "note"])
        dt += timedelta(seconds=60)
'

    # Populate corpora
    echo "Grocery shopping" > /app/corpora/clean/1.txt
    echo "Payment for services" > /app/corpora/clean/2.txt
    echo "Invoice 123" > /app/corpora/clean/3.txt

    echo "System TEST run" > /app/corpora/evil/1.txt
    echo "Product DEMO" > /app/corpora/evil/2.txt
    echo "Account 9876 funding" > /app/corpora/evil/3.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
