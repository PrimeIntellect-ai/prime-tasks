#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr gcc make fonts-dejavu-core
    pip3 install pytest pillow

    mkdir -p /app

    cat << 'EOF' > /app/updates.csv
ADD,5,6,1.0
UPD,1,3,1.0
DEL,2,4,0.0
EOF

    cat << 'EOF' > /app/queries.csv
1,2
1,6
3,4
EOF

    cat << 'EOF' > /tmp/gen_img.py
from PIL import Image, ImageDraw, ImageFont
img = Image.new('RGB', (400, 300), color='white')
d = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 24)
except:
    font = ImageFont.load_default()
text = """Source Target Cost
1 2 5.0
1 3 2.0
3 2 1.5
2 4 4.0
3 4 8.0
4 5 3.0"""
d.text((20, 20), text, fill='black', font=font)
img.save('/app/init_topology.png')
EOF
    python3 /tmp/gen_img.py
    rm /tmp/gen_img.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
