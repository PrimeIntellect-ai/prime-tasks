#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest Pillow

mkdir -p /app

cat << 'EOF' > /tmp/setup.py
import zipfile
import tarfile
import os
from PIL import Image, ImageDraw

# Create image
img = Image.new('RGB', (400, 100), color = (255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,10), "/home/user/restored_data", fill=(0,0,0))
img.save("/app/recovery_instructions.png")

# Create sample backup
with zipfile.ZipFile("/tmp/sample_nested.zip", "w") as z:
    z.writestr("safe_sample.txt", "safe")
    info = zipfile.ZipInfo("../../../tmp/evil_sample.txt")
    z.writestr(info, "evil")

with tarfile.open("/app/sample_backup.tar.gz", "w:gz") as t:
    t.add("/tmp/sample_nested.zip", arcname="sample_nested.zip")

# Create hidden eval backup
with zipfile.ZipFile("/tmp/hidden_nested.zip", "w") as z:
    z.writestr("safe.txt", "safe eval")
    info1 = zipfile.ZipInfo("../../../tmp/eval_restored_data_evil/evil.txt")
    z.writestr(info1, "evil1")
    info2 = zipfile.ZipInfo("/absolute/path/evil2.txt")
    z.writestr(info2, "evil2")

with tarfile.open("/tmp/hidden_eval_backup.tar.gz", "w:gz") as t:
    t.add("/tmp/hidden_nested.zip", arcname="nested.zip")
EOF

python3 /tmp/setup.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
