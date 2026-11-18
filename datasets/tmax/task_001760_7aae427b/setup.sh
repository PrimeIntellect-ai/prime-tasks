#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr sqlite3
    pip3 install --default-timeout=100 pytest flask pillow pytesseract

    mkdir -p /app
    mkdir -p /home/user

    # Create screenshot
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (800, 200), color = (73, 109, 137))
d = ImageDraw.Draw(img)
d.text((10,10), 'Error accessing profile. User ID: USR-9942A. API Token: SEC-7719-XY. Connection dropped.', fill=(255,255,0))
img.save('/app/ticket_screenshot.png')
"

    # Create payload
    cat << 'EOF' > /home/user/ticket_payload.json
{"include_archived": true, "sort": "desc", "limit": 100, "status": "pending", "region": "US-West", "department": "sales"}
EOF

    # Create db
    sqlite3 /home/user/records.db "CREATE TABLE records (id INTEGER PRIMARY KEY, archived INTEGER, data TEXT); INSERT INTO records (archived, data) VALUES (1, 'test1'), (0, 'test2');"

    # Create api_server.py
    cat << 'EOF' > /home/user/api_server.py
from flask import Flask, request, jsonify
import sqlite3

app = Flask(__name__)

@app.route('/api/v1/records/<user_id>', methods=['GET'])
def get_records(user_id):
    token = request.args.get('token')
    if token != 'SEC-7719-XY':
        return jsonify({'error': 'Unauthorized'}), 401

    payload = request.get_json(silent=True) or request.args

    # Convert string to bool if it comes from query args
    include_archived = payload.get('include_archived')
    if isinstance(include_archived, str):
        include_archived = include_archived.lower() == 'true'

    sort = payload.get('sort')

    query = "SELECT * FROM records"

    # Bug: wrong order of WHERE and ORDER BY
    if sort == 'desc':
        query += " ORDER BY id DESC"

    if include_archived:
        query += " WHERE archived=1"

    try:
        conn = sqlite3.connect('/home/user/records.db')
        cur = conn.cursor()
        cur.execute(query)
        rows = cur.fetchall()
        conn.close()
        return jsonify({'data': rows})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8080)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
