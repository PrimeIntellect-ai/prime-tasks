#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest Pillow pytesseract

    # Create directories
    mkdir -p /home/user/images
    mkdir -p /home/user/deployments
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Generate image and corpora
    python3 -c "
import os
import json
from PIL import Image, ImageDraw

# Generate Image
img = Image.new('RGB', (400, 100), color=(0, 0, 0))
d = ImageDraw.Draw(img)
d.text((10, 10), 'Error booting. CLUSTER_ID: VMC-992-KAPPA', fill=(255, 255, 255))
img.save('/app/vnc_screenshot.png')

cluster_id = 'VMC-992-KAPPA'

# Generate Clean Corpus (10 files)
for i in range(10):
    data = {
        'service_name': f'clean-service-{i}',
        'vnc_port': 5900 + i,
        'vm_image_path': f'img_{i}.qcow2',
        'cluster_id': cluster_id
    }
    with open(f'/app/corpora/clean/req_{i}.json', 'w') as f:
        json.dump(data, f)

# Generate Evil Corpus (15 files)
evil_cases = [
    (22, 'img.qcow2', cluster_id),
    (6000, 'img.qcow2', cluster_id),
    (5900, '../img.qcow2', cluster_id),
    (5901, 'img.qcow2', 'VMC-992-KAPPB'),
    (5902, '../../etc/passwd', cluster_id),
    (5903, 'dir/../../img.qcow2', cluster_id),
    (80, 'img.qcow2', 'WRONG'),
    (5904, '/absolute/path.qcow2', cluster_id),
    (5905, 'img.qcow2', 'VMC-992-KAPPAA'),
    (5906, 'img.qcow2', ''),
    (5907, 'subdir/../../../img.qcow2', cluster_id),
    (5899, 'img.qcow2', cluster_id),
    (5908, 'img.qcow2', 'VMC-992-KAPPA '),
    (5909, 'img.qcow2\x00', cluster_id),
    (5910, '~/.bashrc', cluster_id)
]

for i, (port, path, cid) in enumerate(evil_cases):
    data = {
        'service_name': f'evil-service-{i}',
        'vnc_port': port,
        'vm_image_path': path,
        'cluster_id': cid
    }
    with open(f'/app/corpora/evil/req_{i}.json', 'w') as f:
        json.dump(data, f)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
