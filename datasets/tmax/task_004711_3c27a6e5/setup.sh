#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip fonts-dejavu tesseract-ocr
    pip3 install pytest Pillow pytesseract

    mkdir -p /app

    # Generate the certificate policy image using Python and Pillow
    python3 -c '
from PIL import Image, ImageDraw, ImageFont
img = Image.new("RGB", (500, 100), color="white")
d = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 24)
except IOError:
    font = ImageFont.load_default()
d.text((10, 40), "COMPLIANCE_KEY=AUDIT2024SEC", fill="black", font=font)
img.save("/app/cert_policy.png")
'

    # Create the oracle audit tool
    cat << 'EOF' > /app/oracle_audit_tool
#!/usr/bin/env python3
import sys

def main():
    if len(sys.argv) != 2:
        sys.exit(1)
    key = b"AUDIT2024SEC"
    input_bytes = sys.argv[1].encode('utf-8')
    result = bytes([ b ^ key[i % len(key)] for i, b in enumerate(input_bytes) ])
    print(result.hex())

if __name__ == "__main__":
    main()
EOF
    chmod +x /app/oracle_audit_tool

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
