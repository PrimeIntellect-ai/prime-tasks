#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest pillow

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    cat << 'EOF' > /tmp/setup.py
import os
from PIL import Image, ImageDraw

img = Image.new('RGB', (800, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), "MC Step-Size Divergence Detected. REJECT if TATA occurs > 5 times in sequence.", fill=(0, 0, 0))
img.save('/app/divergence_note.png')

def create_fasta(path, num_tata):
    seq = "A" * 10 + "TATA" * num_tata + "C" * 10
    lines = [seq[i:i+80] for i in range(0, len(seq), 80)]
    with open(path, 'w') as f:
        f.write(">sequence\n")
        f.write("\n".join(lines) + "\n")

for i in range(6):
    create_fasta(f"/app/corpus/clean/seq_{i}.fasta", i)

for i in range(6, 12):
    create_fasta(f"/app/corpus/evil/seq_{i}.fasta", i)
EOF

    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
