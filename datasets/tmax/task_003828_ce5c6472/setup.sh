#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr netcat-openbsd gawk sed grep
    pip3 install pytest Pillow

    mkdir -p /app

    cat << 'EOF' > /app/system_metrics.log
[2023-10-15 08:12:45] alice.smith@example.com GET 120
[2023-10-15 08:45:10] bob.jones@corp.local POST 131
[2023-10-15 09:05:00] charlie@test.org GET 200
[2023-10-15 09:59:59] admin@domain.com DELETE 220
EOF

    cat << 'EOF' > /tmp/make_image.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (800, 200), color = (255, 255, 255))
d = ImageDraw.Draw(img)
text = r"""PORT=9099
MASK_REGEX=[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"""
d.text((10,10), text, fill=(0,0,0))
img.save('/app/config_image.png')
EOF
    python3 /tmp/make_image.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
