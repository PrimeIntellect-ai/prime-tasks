#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr sqlite3 tshark
    pip3 install pytest flask scapy pillow

    mkdir -p /app

    # Create the SQLite database and leave the uncommitted data in the WAL
    cat << 'EOF' > /app/create_db.py
import sqlite3
import os

conn = sqlite3.connect('/app/state.db')
conn.execute('PRAGMA journal_mode=WAL;')
conn.execute('CREATE TABLE config(key TEXT, value TEXT);')
conn.commit()

conn.execute("INSERT INTO config VALUES ('AUTH_TOKEN', 'token_xyz_98765');")
conn.commit()

# Exit immediately without closing the connection to preserve the WAL file
os._exit(0)
EOF
    python3 /app/create_db.py

    # Create the pcap file
    cat << 'EOF' > /app/create_pcap.py
from scapy.all import Ether, IP, TCP, Raw, wrpcap

p1 = Ether()/IP(dst="127.0.0.1")/TCP(dport=8888)/Raw(load="POST /compute HTTP/1.1\r\nHost: 127.0.0.1:8888\r\n\r\n{\"value\": 10}")
p2 = Ether()/IP(dst="127.0.0.1")/TCP(dport=8888)/Raw(load="POST /compute HTTP/1.1\r\nHost: 127.0.0.1:8888\r\n\r\n{\"value\": -1}")

wrpcap('/app/requests.pcap', [p1, p2])
EOF
    python3 /app/create_pcap.py

    # Create the equation image
    cat << 'EOF' > /app/create_img.py
from PIL import Image, ImageDraw

img = Image.new('RGB', (200, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), "MODULUS=9973", fill=(0, 0, 0))
img.save('/app/equation.png')
EOF
    python3 /app/create_img.py

    # Create the server code
    cat << 'EOF' > /app/server.py
from flask import Flask, request, jsonify
import math

app = Flask(__name__)

MODULUS = 1 # To be updated

@app.route('/compute', methods=['POST'])
def compute_series():
    data = request.json
    val = data.get('value', 0)
    # causes crash if val < 0
    res = math.sqrt(val) * MODULUS
    return jsonify({"result": res})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8888)
EOF

    # Cleanup setup scripts
    rm /app/create_db.py /app/create_pcap.py /app/create_img.py

    # Ensure WAL exists just in case
    touch /app/state.db-wal

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
