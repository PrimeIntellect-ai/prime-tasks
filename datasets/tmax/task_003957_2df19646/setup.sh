#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest pillow

    mkdir -p /app

    # Generate evidence.png
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 40), 'SECRET: b4sh_s3cr3t_99', fill=(0, 0, 0))
img.save('/app/evidence.png')
"

    # Create jwt_oracle
    cat << 'EOF' > /app/jwt_oracle
#!/usr/bin/env python3
import sys
import base64
import json
import hmac
import hashlib

def main():
    if len(sys.argv) != 2:
        print("INVALID")
        sys.exit(1)
    token = sys.argv[1]
    parts = token.split('.')
    if len(parts) != 3:
        print("INVALID")
        sys.exit(1)
    try:
        header_pad = parts[0] + '=' * (-len(parts[0]) % 4)
        header_json = base64.urlsafe_b64decode(header_pad).decode('utf-8')
        header = json.loads(header_json)
        if header.get('alg', '').upper() != 'HS256':
            print("INVALID")
            sys.exit(1)

        msg = parts[0] + '.' + parts[1]
        sig_pad = parts[2] + '=' * (-len(parts[2]) % 4)
        sig = base64.urlsafe_b64decode(sig_pad)
        expected_sig = hmac.new(b'b4sh_s3cr3t_99', msg.encode('utf-8'), hashlib.sha256).digest()

        if hmac.compare_digest(sig, expected_sig):
            print("VALID")
            sys.exit(0)
        else:
            print("INVALID")
            sys.exit(1)
    except Exception:
        print("INVALID")
        sys.exit(1)

if __name__ == '__main__':
    main()
EOF
    chmod +x /app/jwt_oracle

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
