#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip make
    pip3 install pytest

    mkdir -p /app/vendored/py-sync-server-1.0.0
    cd /app/vendored/py-sync-server-1.0.0

    cat << 'EOF' > server.py
import threading
import json
import socket
from http.server import BaseHTTPRequestHandler, HTTPServer
import compute_utils

lock_A = threading.Lock()
lock_B = threading.Lock()

class SyncHTTPRequestHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/sync':
            auth = self.headers.get('Authorization')
            if auth != 'Bearer secret-token-123':
                self.send_response(401)
                self.end_headers()
                return

            content_length = int(self.headers.get('Content-Length', 0))
            post_data = self.rfile.read(content_length)
            data = json.loads(post_data)

            with lock_A:
                with lock_B:
                    res = compute_utils.calculate_convergence(data['data'], data['threshold'])

            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"result": res}).encode())
        else:
            self.send_response(404)
            self.end_headers()

def run_http_server():
    server_address = ('127.0.0.1', 8080)
    httpd = HTTPServer(server_address, SyncHTTPRequestHandler)
    httpd.serve_forever()

def run_tcp_server():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('127.0.0.1', 8081))
    s.listen(5)
    while True:
        conn, addr = s.accept()
        threading.Thread(target=handle_tcp, args=(conn,)).start()

def handle_tcp(conn):
    try:
        data = conn.recv(1024).decode().strip()
        if not data:
            return
        parts = data.split('|')
        arr = [int(x) for x in parts[0].split(',')]
        threshold = int(parts[1])

        with lock_B:
            with lock_A:
                res = compute_utils.calculate_convergence(arr, threshold)

        conn.sendall(f"{res}\n".encode())
    except Exception as e:
        pass
    finally:
        conn.close()

if __name__ == '__main__':
    threading.Thread(target=run_http_server, daemon=True).start()
    run_tcp_server()
EOF

    cat << 'EOF' > compute_utils.py
def calculate_convergence(data, threshold):
    val = sum(data)
    while val > threshold:
        delta = val * 0.1
        val -= delta
    return val
EOF

    python3 -m py_compile compute_utils.py
    mv __pycache__/compute_utils.*.pyc compute_utils.pyc
    rm compute_utils.py
    rm -rf __pycache__

    cat << 'EOF' > Makefile
PYTHON=python2

run:
	$(PYTHON) server.py
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
