#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    # Create vendored package
    mkdir -p /app/vendored/telemetry-decoder
    touch /app/vendored/__init__.py
    touch /app/vendored/telemetry-decoder/__init__.py

    cat << 'EOF' > /app/vendored/telemetry-decoder/decoder.py
import json

error_cache = {}

def decode(payload_bytes):
    try:
        payload_str = payload_bytes.decode("utf-8")
        data = json.loads(payload_str)
        for k, v in data.items():
            if k.endswith("_coord"):
                data[k] = float(v)
        return data
    except Exception as e:
        error_cache[payload_bytes] = str(e)
        raise
EOF

    # Create service directory and git repo
    mkdir -p /app/service
    cd /app/service
    git init
    git config user.email "engineer@example.com"
    git config user.name "Engineer"

    echo 'SECRET = "sk_live_9f8d7c6b5a4e3f2d1c0b"' > config.py
    git add config.py
    git commit -m "Initial commit: Add config"

    echo 'SECRET = "TODO"' > config.py
    git add config.py
    git commit -m "Fix: Remove hardcoded secret"

    # Create server.py
    cat << 'EOF' > /app/service/server.py
import sys
sys.path.append("/app/vendored")
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import config
from telemetry_decoder import decoder

class RequestHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != '/ingest':
            self.send_response(404)
            self.end_headers()
            return

        auth_header = self.headers.get('Authorization')
        if auth_header != f"Bearer {config.SECRET}":
            self.send_response(401)
            self.end_headers()
            return

        content_length = int(self.headers.get('Content-Length', 0))
        post_data = self.rfile.read(content_length)

        try:
            data = decoder.decode(post_data)
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()

            def default_serializer(obj):
                import decimal
                if isinstance(obj, decimal.Decimal):
                    return str(obj)
                raise TypeError

            self.wfile.write(json.dumps(data, default=default_serializer).encode('utf-8'))
        except Exception as e:
            self.send_response(500)
            self.end_headers()

def run(server_class=HTTPServer, handler_class=RequestHandler, port=8080):
    server_address = ('127.0.0.1', port)
    httpd = server_class(server_address, handler_class)
    httpd.serve_forever()

if __name__ == '__main__':
    run()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
