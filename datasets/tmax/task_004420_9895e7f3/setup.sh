#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest flask pillow pytesseract

    mkdir -p /app
    mkdir -p /home/user/build

    # Generate reference.png and memdump.raw
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (300, 50), color = (255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,10), 'CONVERGENCE_OK_892', fill=(0,0,0))
img.save('/app/reference.png')

import os
with open('/app/memdump.raw', 'wb') as f:
    f.write(os.urandom(1024))
    f.write(b'MEM_SEC_0xFA9B')
    f.write(os.urandom(1024))
"

    # Create processor.py
    cat << 'EOF' > /home/user/build/processor.py
def process_matrix(matrix):
    max_iters = len(matrix)
    i = 0
    while i <= max_iters:
        matrix[i] = matrix[i] * 2
        i += 1
    return matrix
EOF

    # Create test_processor.py
    cat << 'EOF' > /home/user/build/test_processor.py
from processor import process_matrix

def test_process():
    matrix = [1, 2, 3]
    try:
        process_matrix(matrix)
        result_label = "CONVERGENCE_OK_892"
    except IndexError:
        result_label = "FAILED"

    assert result_label == "FIXME"
EOF

    # Create deploy.py
    cat << 'EOF' > /home/user/build/deploy.py
from flask import Flask, jsonify
import os

app = Flask(__name__)

@app.route('/health')
def health():
    token = "UNKNOWN"
    if os.path.exists('/home/user/build_token.txt'):
        with open('/home/user/build_token.txt', 'r') as f:
            token = f.read().strip()
    return jsonify({"status": "running", "token": token})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
