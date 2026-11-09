#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest pytesseract Pillow flask

    mkdir -p /app
    mkdir -p /home/user

    # Generate the test image
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (300, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), \"O'Reilly-INV-88392-A\", fill=(0, 0, 0))
img.save('/app/customer_upload.png')
"

    # Create buggy server.py
    cat << 'EOF' > /home/user/server.py
import sqlite3
from flask import Flask, request, jsonify
import pytesseract
from PIL import Image
import io

app = Flask(__name__)

@app.route('/process', methods=['POST'])
def process():
    auth = request.headers.get('Authorization')
    if auth != 'Bearer diag-token-xyz':
        return "Unauthorized", 401

    if 'file' in request.files:
        file = request.files['file']
        img = Image.open(file)
    else:
        img = Image.open(io.BytesIO(request.data))

    text = pytesseract.image_to_string(img).strip()

    # Buggy SQL query
    conn = sqlite3.connect(':memory:')
    c = conn.cursor()
    c.execute("CREATE TABLE records (id TEXT)")
    query = f"INSERT INTO records VALUES ('{text}')"
    c.execute(query) # Crashes on single quote

    return jsonify({"extracted_text": text})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8080)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
