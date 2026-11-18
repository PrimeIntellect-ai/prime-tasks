#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest flask fastapi uvicorn pandas pyarrow fastparquet chardet pillow requests

    mkdir -p /app/data

    # Create the config memo image
    python3 -c '
from PIL import Image, ImageDraw
img = Image.new("RGB", (400, 200), color="white")
d = ImageDraw.Draw(img)
d.text((10,10), "CONFIDENTIAL\nAPI_TOKEN: SECRET-99X-2024\nKeep this secure.", fill="black")
img.save("/app/config_memo.png")
'

    # Create the CSV files with different encodings
    echo "date,amount
2024-01-01,10.0
2024-01-02,20.0" > /app/data/data1.csv

    python3 -c '
with open("/app/data/data2.csv", "w", encoding="utf-16") as f:
    f.write("date,amount\n2024-01-03,30.0\n")

with open("/app/data/data3.csv", "w", encoding="shift_jis") as f:
    f.write("date,amount\n2024-01-04,40.0\n2024-01-05,50.0\n")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
