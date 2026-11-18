#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu-core gcc libc6-dev
    pip3 install pytest

    # Create directories
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Generate config image
    convert -size 600x200 xc:white -font DejaVu-Sans -pointsize 36 -fill black -draw "text 20,60 'REF_VECTOR: 2.0, -1.0, 2.0' text 20,120 'THRESHOLD: 0.85'" /app/config.png

    # Generate CSV files
    cat << 'EOF' > /tmp/gen_csv.py
import csv

clean_dir = "/app/corpora/clean"
evil_dir = "/app/corpora/evil"

for i in range(5):
    with open(f"{clean_dir}/clean_{i}.csv", "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["id", "x", "y", "z"])
        writer.writerow([1, 2.0, -1.0, 2.0])
        writer.writerow([2, 2.1, -0.9, 1.9])
        writer.writerow([3, 1.9, -1.1, 2.1])

evil_rows = [
    [99, 0.0, 0.0, 0.0],
    [98, -2.0, 1.0, -2.0],
    [97, 2.0, 5.0, 2.0],
    [96, 1.0, 10.0, 1.0],
    [95, -1.0, -1.0, -1.0]
]

for i in range(5):
    with open(f"{evil_dir}/evil_{i}.csv", "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["id", "x", "y", "z"])
        writer.writerow([1, 2.0, -1.0, 2.0])
        writer.writerow(evil_rows[i])
        writer.writerow([2, 2.1, -0.9, 1.9])
EOF
    python3 /tmp/gen_csv.py
    rm /tmp/gen_csv.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
