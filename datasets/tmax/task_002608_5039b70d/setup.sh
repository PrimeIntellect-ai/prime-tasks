#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        unzip \
        gzip \
        tar \
        libtesseract-dev

    pip3 install pytest Pillow pytesseract

    mkdir -p /app

    cat << 'EOF' > /tmp/setup.py
import os
import tarfile
import zipfile
from PIL import Image, ImageDraw, ImageFont
import shutil

# 1. Create base directory
os.makedirs('/app/backup_root/nested_dir', exist_ok=True)

# 2. Create the Image Note
img = Image.new('RGB', (200, 100), color = (255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,10), "XOR_KEY=87", fill=(0,0,0))
img.save('/app/note.png')

# 3. Create normal text file
with open('/app/backup_root/file_a.txt', 'w') as f:
    f.write("import sys\nprint('hello')\ndef process():\n    pass\n")

# 4. Create enc file
xor_key = 87
def create_enc(path, text):
    with open(path, 'wb') as f:
        f.write(bytes([ord(c) ^ xor_key for c in text]))

create_enc('/app/backup_root/nested_dir/file_b.enc', "print('hello')\n# redundant comment\ndef process():\n    pass\n")

# 5. Create a nested zip
os.makedirs('/tmp/zip_contents', exist_ok=True)
create_enc('/tmp/zip_contents/file_c.enc', "import sys\n# unique content\nprint('world')\n")
with zipfile.ZipFile('/app/backup_root/nested_dir/archive.zip', 'w') as zf:
    zf.write('/tmp/zip_contents/file_c.enc', 'file_c.enc')

# 6. Create symlink loop
os.symlink('../', '/app/backup_root/nested_dir/loop_link')

# 7. Create tarball
with tarfile.open('/app/project_backup.tar', 'w') as tar:
    tar.add('/app/backup_root', arcname='backup_root')

# 8. Cleanup un-tarred
shutil.rmtree('/app/backup_root')
EOF

    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
