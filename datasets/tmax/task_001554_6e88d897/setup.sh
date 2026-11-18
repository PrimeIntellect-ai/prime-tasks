#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest Pillow

    mkdir -p /app

    # Generate the image with the required text
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = '''TRACK MAPPING:
A -> 2
C -> -1
G -> 3
T -> -2
KERNEL: [1, -1, 2]'''
d.text((10,10), text, fill=(0,0,0))
img.save('/app/motif_spec.png')
"

    # Create the oracle script
    cat << 'EOF' > /app/oracle_filter.py
#!/usr/bin/env python3
import sys

def main():
    if len(sys.argv) < 2:
        return
    seq = sys.argv[1].upper()
    mapping = {'A': 2, 'C': -1, 'G': 3, 'T': -2}
    kernel = [1, -1, 2]

    nums = [mapping.get(c, 0) for c in seq]

    if len(nums) < len(kernel):
        print("")
        return

    out = []
    for i in range(len(nums) - len(kernel) + 1):
        val = (nums[i] * kernel[0] + 
               nums[i+1] * kernel[1] + 
               nums[i+2] * kernel[2])
        out.append(str(val))

    print(" ".join(out))

if __name__ == "__main__":
    main()
EOF
    chmod +x /app/oracle_filter.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
