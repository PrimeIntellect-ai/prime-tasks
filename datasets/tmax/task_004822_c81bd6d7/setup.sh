#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr fonts-dejavu
    pip3 install pytest pytesseract Pillow

    mkdir -p /app/clean /app/evil

    # Create the policy memo image
    python3 -c "
from PIL import Image, ImageDraw, ImageFont
img = Image.new('RGB', (800, 200), color='white')
d = ImageDraw.Draw(img)
font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 30)
d.text((10, 50), 'MANDATORY REDACTION SALT: COMPLIANCE_v7_8923', font=font, fill='black')
img.save('/app/policy_memo.png')
"

    # Create dummy clean corpus
    cat << 'EOF' > /app/clean/clean1.json
{
  "endpoint": "/api/v1/login",
  "method": "POST",
  "headers": {
    "User-Agent": "Mozilla/5.0",
    "Content-Security-Policy": "default-src 'self'"
  },
  "payload": {
    "username": "admin",
    "password": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  }
}
EOF

    # Create dummy evil corpus
    cat << 'EOF' > /app/evil/evil1.json
{
  "endpoint": "/api/v1/login",
  "method": "POST",
  "headers": {
    "User-Agent": "Mozilla/5.0"
  },
  "payload": {
    "username": "<script>alert(1)</script>",
    "password": "my_plaintext_password"
  }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
