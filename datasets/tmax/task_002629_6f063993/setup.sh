#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip make socat
    pip3 install pytest

    mkdir -p /app/iot-gateway-2.1.0
    cat << 'EOF' > /app/iot-gateway-2.1.0/gatewayd
#!/usr/bin/env python3
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

class GatewayHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            token = os.environ.get('GATEWAY_AUTH_TOKEN', '')
            if token == 'edge2024':
                self.send_response(200)
                self.send_header('Content-type', 'text/plain')
                self.end_headers()
                self.wfile.write(b"OK - Authorized")
            else:
                self.send_response(403)
                self.send_header('Content-type', 'text/plain')
                self.end_headers()
                self.wfile.write(b"Forbidden")
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 8080), GatewayHandler)
    server.serve_forever()
EOF
    chmod +x /app/iot-gateway-2.1.0/gatewayd

    cat << 'EOF' > /app/iot-gateway-2.1.0/Makefile
PREFIX ?= /usr/local
BINDIR = $(PREFIX)/bin

install:
	mkdir -p $(BINDIR)
	cp gatewayd $(BINDIR)/
	chmod +x $(BINDIR)/gatewayd
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
