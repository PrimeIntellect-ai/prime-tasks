#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest Pillow

    mkdir -p /app

    # Create the oracle program
    cat << 'EOF' > /app/legacy_encoder_oracle
#!/usr/bin/env python3
import sys
import base64

def main():
    data = sys.stdin.read()
    reversed_data = data[::-1]
    xored = bytearray()
    for char in reversed_data:
        xored.append(ord(char) ^ 0x5C)
    encoded = base64.b64encode(xored).decode('ascii')
    sys.stdout.write(encoded)

if __name__ == '__main__':
    main()
EOF
    chmod +x /app/legacy_encoder_oracle

    # Generate the image using Python and Pillow
    cat << 'EOF' > /tmp/gen_image.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (800, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = """LEGACY AUTH ENCODING ALGORITHM:
1. Read raw string from input.
2. Reverse the entire string.
3. XOR each character's byte value with the hexadecimal key 0x5C.
4. Base64 encode the resulting byte array.
5. Output the Base64 string."""
d.text((10, 10), text, fill=(0, 0, 0))
img.save('/app/legacy_auth_spec.png')
EOF
    python3 /tmp/gen_image.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
