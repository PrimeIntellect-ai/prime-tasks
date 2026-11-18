#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /app/src

    cat << 'EOF' > /app/src/db.py
import socket, json
s = socket.socket()
s.bind(('127.0.0.1', 7070))
s.listen(5)
while True:
    conn, _ = s.accept()
    data = conn.recv(1024)
    if data:
        conn.sendall(b'{"status": "saved"}')
    conn.close()
EOF

    cat << 'EOF' > /app/src/worker.py
import socket, struct, traceback
def process_tx(conn):
    try:
        # BUG: Reading 4 bytes and unpacking as 32-bit float causes precision loss on large integers
        data = conn.recv(4) 
        if not data: return
        tx_id = struct.unpack('f', data)[0]
        tx_id = int(tx_id)

        # Simulated database logic
        db_s = socket.socket()
        db_s.connect(('127.0.0.1', 7070))
        db_s.sendall(str(tx_id).encode())
        db_s.recv(1024)
        db_s.close()

        # Bug consequence: exact matching fails due to precision loss
        conn.sendall(str(tx_id).encode())
    except Exception as e:
        with open("/tmp/worker.log", "a") as f:
            traceback.print_exc(file=f)
        raise e

s = socket.socket()
s.bind(('127.0.0.1', 9090))
s.listen(5)
while True:
    conn, _ = s.accept()
    process_tx(conn)
    conn.close()
EOF

    cat << 'EOF' > /app/src/gateway.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import json, socket, struct

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length)
        req = json.loads(post_data)
        tx_id = req['tx_id']

        # BUG: Packing 64-bit int into 32-bit float
        packed_data = struct.pack('f', float(tx_id))

        s = socket.socket()
        s.connect(('127.0.0.1', 9090))
        s.sendall(packed_data)
        resp = s.recv(1024)
        s.close()

        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps({"status": "success", "processed_id": int(resp.decode())}).encode())

httpd = HTTPServer(('127.0.0.1', 8080), Handler)
httpd.serve_forever()
EOF

    chmod -R 777 /app
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
