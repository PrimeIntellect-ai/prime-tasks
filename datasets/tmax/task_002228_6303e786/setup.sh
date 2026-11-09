#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest Pillow

    python3 -c "
import os
from PIL import Image, ImageDraw

os.makedirs('/app/corpus/clean', exist_ok=True)
os.makedirs('/app/corpus/evil', exist_ok=True)
os.makedirs('/app/verifier/clean', exist_ok=True)
os.makedirs('/app/verifier/evil', exist_ok=True)

img = Image.new('RGB', (400, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 40), 'SYSTEM_AUTH_TOKEN=VORTEX_77X', fill=(0, 0, 0))
img.save('/app/auth_token_schema.png')

clean_line = '2023-10-12 12:00:00 TX-1234 VORTEX_77X SET CONFIG_VAR value_1\n'
for i in range(5):
    with open(f'/app/corpus/clean/log_{i}.log', 'w') as f:
        f.write(clean_line * 3)
    with open(f'/app/verifier/clean/log_{i}.log', 'w') as f:
        f.write(clean_line * 3)

evil_line_1 = '2023-10-12 12:00:00 TX-1234 VORTEX_99X SET CONFIG_VAR value_1\n'
evil_line_2 = '2023-10-12 12:00:00 TX-1234 VORTEX_77X ESCALATE CONFIG_VAR value_1\n'
for i in range(5):
    with open(f'/app/corpus/evil/log_{i}.log', 'w') as f:
        f.write(clean_line + evil_line_1 + clean_line)
    with open(f'/app/verifier/evil/log_{i}.log', 'w') as f:
        f.write(clean_line + evil_line_2 + clean_line)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
