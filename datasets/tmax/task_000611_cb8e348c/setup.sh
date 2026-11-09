#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr g++ curl tar gzip
    pip3 install pytest Pillow

    mkdir -p /app
    useradd -m -s /bin/bash user || true

    python3 -c "
import os
import tarfile
import random
import struct
from PIL import Image, ImageDraw

os.makedirs('/app', exist_ok=True)
img = Image.new('RGB', (600, 200), color='white')
d = ImageDraw.Draw(img)
text = 'System Recovery Info:\nMAGIC_HEADER = 0xDE 0xAD 0xBE 0xEF\nAUTH_TOKEN = secr3t_lab_77xyz'
d.text((10,10), text, fill='black')
img.save('/app/lab_note.png')

os.makedirs('/tmp/dataset', exist_ok=True)
for i in range(1, 4):
    with open(f'/tmp/dataset/log{i}.txt', 'w') as f:
        f.write(f'Log {i} data\n')
        f.write('Some valid data SENSOR_NODE_005 more data\n')
        f.write('Error: [ERR_CALIBRATION_LOSS] occurred\n')

with tarfile.open('/tmp/dataset.tar.gz', 'w:gz') as tar:
    tar.add('/tmp/dataset', arcname='.')

with open('/tmp/dataset.tar.gz', 'rb') as f:
    tar_data = f.read()

magic = b'\xEF\xBE\xAD\xDE'
out_data = bytearray()

chunk_size = 100
offset = 0
while offset < len(tar_data):
    out_data.extend(os.urandom(random.randint(10, 50)))
    c_size = min(chunk_size, len(tar_data) - offset)
    out_data.extend(magic)
    out_data.extend(struct.pack('<I', c_size))
    out_data.extend(tar_data[offset:offset+c_size])
    offset += c_size

out_data.extend(os.urandom(random.randint(10, 50)))

with open('/home/user/raw_sensor.bin', 'wb') as f:
    f.write(out_data)
"

    chmod -R 777 /home/user
    chmod -R 777 /app
