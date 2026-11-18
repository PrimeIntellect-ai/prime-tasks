#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr g++ rustc
    pip3 install pytest pillow

    mkdir -p /app

    # Generate the image
    cat << 'EOF' > /tmp/gen_image.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (800, 100), color = (255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,10), "T(n) = (n^3 - 5n + 12) mod 997. Sort in descending order, remove duplicates.", fill=(0,0,0))
img.save('/app/formula.png')
EOF
    python3 /tmp/gen_image.py

    # Create the oracle binary
    cat << 'EOF' > /app/oracle_bin
#!/usr/bin/env python3
import sys

def T(n):
    return (((n**3 - 5*n + 12) % 997) + 997) % 997

def main():
    input_data = sys.stdin.read().split()
    if not input_data:
        return

    transformed = []
    for x in input_data:
        try:
            n = int(x)
            transformed.append(T(n))
        except ValueError:
            pass

    result = sorted(list(set(transformed)), reverse=True)
    print(" ".join(map(str, result)))

if __name__ == '__main__':
    main()
EOF
    chmod +x /app/oracle_bin

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
