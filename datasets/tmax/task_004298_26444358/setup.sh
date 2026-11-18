#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest Pillow

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    python3 -c "
import os
import tarfile
from PIL import Image, ImageDraw

# Generate policy image
img = Image.new('RGB', (1000, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = \"CRITICAL POLICY: Any log containing the sequence 'FATAL_LOOP_EXCEPTION_x8891' must be immediately purged to save disk space.\"
d.text((10, 50), text, fill=(0, 0, 0))
img.save('/app/policy.png')

# Generate clean and evil tarballs
for i in range(1, 51):
    # Clean
    clean_log = f'clean_{i:02d}.log'
    with open(clean_log, 'w') as f:
        f.write(f'Standard log entry {i}\\nEverything is fine.\\n')
    with tarfile.open(f'/app/corpus/clean/clean_{i:02d}.tar.gz', 'w:gz') as tar:
        tar.add(clean_log)
    os.remove(clean_log)

    # Evil
    evil_log = f'evil_{i:02d}.log'
    with open(evil_log, 'w') as f:
        f.write(f'Standard log entry {i}\\nFATAL_LOOP_EXCEPTION_x8891\\nOh no!\\n')
    with tarfile.open(f'/app/corpus/evil/evil_{i:02d}.tar.gz', 'w:gz') as tar:
        tar.add(evil_log)
    os.remove(evil_log)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
