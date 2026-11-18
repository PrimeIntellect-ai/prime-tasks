#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr nginx
    pip3 install pytest Pillow

    mkdir -p /app
    mkdir -p /home/user

    # Generate the image
    cat << 'EOF' > /tmp/gen_img.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (800, 200), color = (255, 255, 255))
d = ImageDraw.Draw(img)
text = "System Status: DEGRADED. Upstream connection failed.\nPlease ensure the proxy is routing to the correct application socket:\nunix:/tmp/secure_app_v4.sock"
d.text((10,10), text, fill=(0,0,0))
img.save('/app/legacy_dashboard.png')
EOF
    python3 /tmp/gen_img.py

    # Create nginx config
    cat << 'EOF' > /home/user/nginx.conf
pid /tmp/nginx.pid;
error_log /tmp/error.log;
events {
    worker_connections 1024;
}
http {
    client_body_temp_path /tmp/client_body;
    fastcgi_temp_path /tmp/fastcgi_temp;
    proxy_temp_path /tmp/proxy_temp;
    scgi_temp_path /tmp/scgi_temp;
    uwsgi_temp_path /tmp/uwsgi_temp;
    access_log /tmp/access.log;
    server {
        listen 127.0.0.1:8080;
        location / {
            proxy_pass http://unix:/tmp/wrong.sock;
        }
    }
}
EOF

    # Create backend script
    cat << 'EOF' > /app/backend.py
import sys
import os
from http.server import BaseHTTPRequestHandler
import socketserver
import socket

class UnixSocketHttpServer(socketserver.TCPServer):
    address_family = socket.AF_UNIX
    def server_bind(self):
        if os.path.exists(self.server_address):
            os.unlink(self.server_address)
        socketserver.TCPServer.server_bind(self)

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"OK")
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    if len(sys.argv) < 2:
        sys.exit(1)
    sock_path = sys.argv[1]
    if sock_path.startswith("unix:"):
        sock_path = sock_path[5:]
    with UnixSocketHttpServer(sock_path, Handler) as httpd:
        httpd.serve_forever()
EOF

    chmod +x /app/backend.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
