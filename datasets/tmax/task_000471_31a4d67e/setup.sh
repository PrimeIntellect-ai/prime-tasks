#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    # Create app directory
    mkdir -p /app/data_aggregator-1.0.0/data_aggregator

    # Create setup.py
    cat << 'EOF' > /app/data_aggregator-1.0.0/setup.py
from setuptools import setup, find_packages

setup(
    name='data_aggregator',
    version='1.0.0',
    packages=find_packages(),
    install_requires=[
        'requests>=2.28.0',
        'urllib3==1.24.0'
    ],
)
EOF

    # Create __init__.py
    touch /app/data_aggregator-1.0.0/data_aggregator/__init__.py

    # Create server.py
    cat << 'EOF' > /app/data_aggregator-1.0.0/data_aggregator/server.py
import threading
import time
import json
import os
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

process_lock = threading.Lock()

def process_payload(payload):
    with process_lock:
        return _internal_process(payload)

def _internal_process(payload):
    with process_lock: # DEADLOCK: standard Lock acquired twice by the same thread
        time.sleep(0.1) # Simulate IO
        return {"status": "success", "processed_value": payload.get("value")}

class RequestHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/process':
            api_key = self.headers.get('X-API-Key')
            if api_key != os.environ.get('AGGREGATOR_API_KEY'):
                self.send_response(403)
                self.end_headers()
                return

            try:
                content_length = int(self.headers.get('Content-Length', 0))
                post_data = self.rfile.read(content_length)
                payload = json.loads(post_data)
            except Exception:
                payload = {}

            try:
                result = process_payload(payload)
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps(result).encode('utf-8'))
            except Exception as e:
                self.send_response(500)
                self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    server_address = ('127.0.0.1', 8080)
    httpd = ThreadingHTTPServer(server_address, RequestHandler)
    httpd.serve_forever()
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /app
    chmod -R 777 /home/user
