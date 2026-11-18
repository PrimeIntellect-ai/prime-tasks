#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest pytesseract Pillow flask fastapi uvicorn pandas numpy requests

    mkdir -p /app

    # Create meta.csv
    cat << 'EOF' > /app/meta.csv
ip,region
10.0.0.1,APAC
10.0.0.2,EMEA
10.0.0.3,NORAM
EOF

    # Create incident_report.png using Python and Pillow
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,30), 'CRITICAL INCIDENT REPORT', fill=(0,0,0))
d.text((10,60), 'LISTEN PORT: 8282', fill=(0,0,0))
d.text((10,90), 'Z_THRESHOLD: 2.0', fill=(0,0,0))
d.text((10,120), 'INVESTIGATE IMMEDIATELY', fill=(0,0,0))
img.save('/app/incident_report.png')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
