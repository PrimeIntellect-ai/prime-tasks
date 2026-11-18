#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
pip3 install pytest Pillow

mkdir -p /app/traces/clean /app/traces/evil

python3 -c "
import os
import random
from PIL import Image, ImageDraw

# Generate the image
img = Image.new('RGB', (400, 100), color='white')
d = ImageDraw.Draw(img)
d.text((20, 50), 'Max allowed R-hat: 1.05', fill='black')
img.save('/app/mcmc_spec.png')

# Generate clean traces
for i in range(5):
    with open('/app/traces/clean/trace_' + str(i) + '.csv', 'w') as f:
        f.write('chain,step,value\n')
        for step in range(100):
            f.write('1,' + str(step) + ',' + str(random.gauss(0, 1)) + '\n')
            f.write('2,' + str(step) + ',' + str(random.gauss(0, 1)) + '\n')

# Generate evil traces
for i in range(5):
    with open('/app/traces/evil/trace_' + str(i) + '.csv', 'w') as f:
        f.write('chain,step,value\n')
        for step in range(100):
            f.write('1,' + str(step) + ',' + str(random.gauss(-2, 0.1)) + '\n')
            f.write('2,' + str(step) + ',' + str(random.gauss(2, 0.1)) + '\n')
"

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user /app
