#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl curl jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/config.json
{
    "port": 443,
    "certfile": "/home/user/cert.pem",
    "keyfile": "/home/user/key.pem"
}
EOF

    cat << 'EOF' > /home/user/server.py
import json
import ssl
import http.server
import sys
import logging

logging.basicConfig(filename='/home/user/server.log', level=logging.ERROR)

try:
    with open('/home/user/config.json') as f:
        config = json.load(f)

    port = config['port']
    certfile = config['certfile']
    keyfile = config['keyfile']

    class HealthHandler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path == '/health':
                self.send_response(200)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(b'{"status": "ok"}')
            else:
                self.send_response(404)
                self.end_headers()
        def log_message(self, format, *args):
            pass

    httpd = http.server.HTTPServer(('127.0.0.1', port), HealthHandler)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(certfile=certfile, keyfile=keyfile)
    httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
    httpd.serve_forever()
except Exception as e:
    logging.error(str(e))
    sys.exit(1)
EOF

    chmod -R 777 /home/user
