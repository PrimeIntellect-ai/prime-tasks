#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest pytesseract Pillow

    mkdir -p /app

    cat << 'EOF' > /tmp/setup.py
import tarfile
import zipfile
import io
import os
from PIL import Image, ImageDraw

os.makedirs('/app', exist_ok=True)

# Generate image
img = Image.new('RGB', (400, 200), color='white')
d = ImageDraw.Draw(img)
d.text((10, 10), "GLOBAL CONFIGURATION OVERRIDES\nMAX_CONNECTIONS=8192\nTIMEOUT=45", fill='black')
img.save('/app/config_schematic.png')

# Generate configs.tar.gz
with tarfile.open('/app/configs.tar.gz', 'w:gz') as tar:
    for i in range(10):
        zip_buffer = io.BytesIO()
        with zipfile.ZipFile(zip_buffer, 'w') as zf:
            for j in range(50):
                content = f"SERVER_ID={i}_{j}\nLOG_LEVEL=DEBUG\nMAX_CONNECTIONS=100\nTIMEOUT=10\n" + ("PADDING=X" * 100) + "\n"
                zf.writestr(f"config_{j}.conf", content)

        zip_buffer.seek(0)
        tarinfo = tarfile.TarInfo(name=f"cluster_{i}.zip")
        tarinfo.size = len(zip_buffer.getvalue())
        tar.addfile(tarinfo, zip_buffer)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
