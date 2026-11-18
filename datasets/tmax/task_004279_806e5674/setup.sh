#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip imagemagick tesseract-ocr fonts-dejavu-core
pip3 install pytest flask

mkdir -p /app
cd /app

# Create the memory dump with random binary data and the hidden string
head -c 1024 /dev/urandom > /app/memory.dmp
echo "DEBUG_SESSION_ID=9928374" >> /app/memory.dmp
head -c 1024 /dev/urandom >> /app/memory.dmp

# Generate the image with the hidden text
convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 10,50 'SYSTEM_OVERRIDE_CODE=OMEGA77'" /app/clue.png

# Create the broken server.py
cat << 'EOF' > /app/server.py
from flask import Flask, request, jsonify

app = Flask(__name__)

@app.route('/status', methods=['GET'])
def status():
    # Bug: crashes if headers are missing
    override = request.headers.get('X-Override-Code')
    session = request.headers.get('X-Session-Id')

    # Intentionally causing an unhandled exception similar to an unwrap() panic
    override_prefix = override.split('_')[0]
    session_val = int(session)

    if override == "TODO" and session == "TODO":
        return jsonify({"status": "recovered"}), 200
    return jsonify({"error": "unauthorized"}), 403

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8000)
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
