#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr tar gzip coreutils
pip3 install pytest Pillow

cat << 'EOF' > /tmp/setup.py
import os
import tarfile
import hashlib
import random
from PIL import Image, ImageDraw

# Create directories
os.makedirs('/app/corpus/clean', exist_ok=True)
os.makedirs('/app/corpus/evil', exist_ok=True)

# Generate image
img = Image.new('RGB', (800, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = "SYSTEM SPECS: PERMITTED ACTIONS ARE [INIT, UPDATE, REVERT]. SECURITY SALT IS [zX9_config]."
d.text((10, 10), text, fill=(0, 0, 0))
img.save('/app/architecture_diagram.png')

salt = "zX9_config"
actions = ["INIT", "UPDATE", "REVERT"]

def make_wal_line(action, key, value, bad_checksum=False):
    ts = "[2023-10-10 10:00:00]"
    s = action + key + salt
    chk = hashlib.md5(s.encode()).hexdigest()
    if bad_checksum:
        chk = "00000000000000000000000000000000"
    return f"{ts} {action} | {key} | {value} | {chk}\n"

def create_archive(path, is_evil):
    os.makedirs('/tmp/wals', exist_ok=True)
    for i in range(3):
        with open(f'/tmp/wals/file_{i}.wal', 'w') as f:
            f.write(make_wal_line(random.choice(actions), f"key{i}", f"val{i}"))
            if is_evil and i == 0:
                if random.choice([True, False]):
                    f.write(make_wal_line("HACK", "keyX", "valX"))
                else:
                    f.write(make_wal_line("INIT", "keyY", "valY", bad_checksum=True))

    with tarfile.open('/tmp/inner.tar.gz', 'w:gz') as tar:
        tar.add('/tmp/wals', arcname='wals')

    with tarfile.open(path, 'w') as tar:
        tar.add('/tmp/inner.tar.gz', arcname='inner.tar.gz')

    for i in range(3):
        os.remove(f'/tmp/wals/file_{i}.wal')
    os.remove('/tmp/inner.tar.gz')

for i in range(5):
    create_archive(f'/app/corpus/clean/clean_{i}.tar', False)
    create_archive(f'/app/corpus/evil/evil_{i}.tar', True)
EOF

python3 /tmp/setup.py
rm /tmp/setup.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
