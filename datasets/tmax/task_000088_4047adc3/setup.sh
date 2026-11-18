#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang tesseract-ocr
    pip3 install --default-timeout=100 pytest Pillow

    mkdir -p /app/corpus/clean /app/corpus/evil

    cat << 'EOF' > /tmp/setup_data.py
import tarfile
import io
from PIL import Image, ImageDraw

# Create image
img = Image.new('RGB', (600, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 40), "REQUIRED FORMAT: SECURELOG_{original_name}.txt", fill=(0, 0, 0))
img.save('/app/target_format.png')

# Create clean tar
with tarfile.open('/app/corpus/clean/app_logs.tar.gz', 'w:gz') as tar:
    for name in ['web.log', 'db.log']:
        info = tarfile.TarInfo(name)
        info.size = 4
        tar.addfile(info, io.BytesIO(b'test'))

# Create evil tars
with tarfile.open('/app/corpus/evil/attack1.tar.gz', 'w:gz') as tar:
    info = tarfile.TarInfo('../../../etc/passwd')
    info.size = 4
    tar.addfile(info, io.BytesIO(b'evil'))

with tarfile.open('/app/corpus/evil/attack2.tar.gz', 'w:gz') as tar:
    info = tarfile.TarInfo('/root/hidden.log')
    info.size = 4
    tar.addfile(info, io.BytesIO(b'evil'))

with tarfile.open('/app/corpus/evil/attack3.tar.gz', 'w:gz') as tar:
    info = tarfile.TarInfo('valid.log')
    info.size = 4
    tar.addfile(info, io.BytesIO(b'test'))
    info2 = tarfile.TarInfo('dir/../../evil.sh')
    info2.size = 4
    tar.addfile(info2, io.BytesIO(b'evil'))
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
