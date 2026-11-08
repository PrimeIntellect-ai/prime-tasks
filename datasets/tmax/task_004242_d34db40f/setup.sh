#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr python3-pil
    pip3 install pytest

    mkdir -p /app/eval_corpora/clean
    mkdir -p /app/eval_corpora/evil

    python3 -c "
from PIL import Image, ImageDraw
import os

text = '''DATA SANITIZATION PROTOCOL
Reject any file if it meets ANY of the following criteria:
1. Contains the exact string 'PHI_RECORD_DETECTED'.
2. Contains 4 or more consecutive asterisks (****).
3. The file has more than 20 lines of text.'''

img = Image.new('RGB', (800, 400), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,10), text, fill=(0,0,0))
img.save('/app/dataset_rules.png')

for i in range(50):
    with open(f'/app/eval_corpora/clean/file_{i}.txt', 'w') as f:
        f.write(f'Clean file {i}\nJust some normal text.\n')

for i in range(50):
    with open(f'/app/eval_corpora/evil/file_{i}.txt', 'w') as f:
        if i % 3 == 0:
            f.write('Some text\nPHI_RECORD_DETECTED\nMore text')
        elif i % 3 == 1:
            f.write('Some text\nLook at this: *****\nMore text')
        else:
            f.write('\n'.join([f'Line {j}' for j in range(25)]))
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
