#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr fonts-liberation
    pip3 install pytest Pillow pytesseract

    mkdir -p /app

    # Create the oracle encoder script
    cat << 'EOF' > /app/oracle_encoder
#!/usr/bin/env python3
import sys
import base64

def custom_b64encode(data: bytes, custom_alphabet: str) -> str:
    std_alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    std_b64 = base64.b64encode(data).decode('utf-8')
    translation_table = str.maketrans(std_alphabet, custom_alphabet)
    return std_b64.translate(translation_table)

def main():
    input_data = sys.stdin.buffer.read()
    if not input_data:
        return

    xor_key = 0x4F
    custom_alphabet = "vwxyzABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstu0123456789+/"

    xored_data = bytes([b ^ xor_key for b in input_data])
    encoded = custom_b64encode(xored_data, custom_alphabet)

    sys.stdout.write(encoded)

if __name__ == "__main__":
    main()
EOF
    chmod +x /app/oracle_encoder

    # Generate the C2 notes image
    python3 -c "
from PIL import Image, ImageDraw, ImageFont
img = Image.new('RGB', (1000, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype('/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf', 24)
except:
    font = ImageFont.load_default()
text = 'C2 Payload Parameters:\nXOR_KEY: 0x4F\nALPHABET: vwxyzABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstu0123456789+/'
d.text((20, 20), text, fill=(0, 0, 0), font=font)
img.save('/app/c2_notes.png')
"

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
