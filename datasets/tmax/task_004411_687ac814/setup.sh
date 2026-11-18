#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install --default-timeout=100 pytest psutil Pillow

    mkdir -p /app
    mkdir -p /home/user

    # Generate the dashboard image
    cat << 'EOF' > /tmp/gen_image.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (800, 200), color=(73, 109, 137))
d = ImageDraw.Draw(img)
d.text((10, 10), "LEAK DETECTED: DataNode_773X_Obfuscated", fill=(255, 255, 0))
img.save('/app/dashboard.png')
EOF
    python3 /tmp/gen_image.py

    # Create service.py
    cat << 'EOF' > /home/user/service.py
import time
import argparse

cache = []

class DataNode_773X_Obfuscated:
    def __init__(self, data):
        self.data = data

class OtherNode:
    def __init__(self, data):
        self.data = data

def process_data(iteration):
    node1 = OtherNode(f"data_{iteration}")
    # 100KB per object to ensure noticeable memory growth
    node2 = DataNode_773X_Obfuscated(f"leak_{iteration}" * 10000)

    cache.append(node2)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--test-mode", action="store_true")
    args = parser.parse_args()

    iteration = 0
    while True:
        process_data(iteration)
        iteration += 1
        if not args.test_mode:
            time.sleep(0.01)
        else:
            time.sleep(0.001)

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
