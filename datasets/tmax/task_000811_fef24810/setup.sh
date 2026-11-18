#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg tesseract-ocr
    pip3 install pytest pillow

    mkdir -p /app/corpus/evil /app/corpus/clean /app/corpus/invalid

    cat << 'EOF' > /tmp/setup.py
import os
import random
from PIL import Image, ImageDraw

def format_txn(i):
    return f"TXN-{i:04d}"

# Generate Clean Corpus (DAGs)
for i in range(50):
    with open(f"/app/corpus/clean/clean_{i}.csv", "w") as f:
        nodes = random.sample(range(1000, 9999), 20)
        nodes.sort()
        for _ in range(30):
            u = random.choice(nodes[:-1])
            v = random.choice([n for n in nodes if n > u])
            f.write(f"{format_txn(u)},{format_txn(v)}\n")

# Generate Evil Corpus (Cycles)
for i in range(50):
    with open(f"/app/corpus/evil/evil_{i}.csv", "w") as f:
        nodes = random.sample(range(1000, 9999), 20)
        nodes.sort()
        for _ in range(30):
            u = random.choice(nodes[:-1])
            v = random.choice([n for n in nodes if n > u])
            f.write(f"{format_txn(u)},{format_txn(v)}\n")
        # Add a backward edge to create a cycle
        f.write(f"{format_txn(nodes[-1])},{format_txn(nodes[0])}\n")

# Generate Invalid Corpus (Malformed Schema)
for i in range(10):
    with open(f"/app/corpus/invalid/invalid_{i}.csv", "w") as f:
        f.write("TXN-123,TXN-1234\n") # Missing a digit
        f.write("TXN-1000,TXN-2000\n")

# Generate Video Frames
os.makedirs("/tmp/frames", exist_ok=True)
for i in range(60):
    img = Image.new('RGB', (800, 600), color=(0, 0, 0))
    d = ImageDraw.Draw(img)
    if i == 30:
        d.text((50, 300), "STRICT CSV SCHEMA: ^TXN-[0-9]{4},TXN-[0-9]{4}$", fill=(255, 255, 255))
    img.save(f"/tmp/frames/frame_{i:03d}.png")

# Compile Video
os.system("ffmpeg -y -framerate 30 -i /tmp/frames/frame_%03d.png -c:v libx264 -pix_fmt yuv420p /app/transaction_visualization.mp4")
EOF

    python3 /tmp/setup.py
    rm -rf /tmp/setup.py /tmp/frames

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
