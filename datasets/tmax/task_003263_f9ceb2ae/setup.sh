#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick
    pip3 install pytest aiohttp

    mkdir -p /app

    # Create the legacy_creds.png image
    convert -size 400x200 xc:white -fill black -pointsize 24 -draw "text 10,50 'Password: SuperSecretLegacy99'" -draw "text 10,100 'BasePort: 8000'" /app/legacy_creds.png

    # Create service_config.json
    cat << 'EOF' > /app/service_config.json
{
    "service_name": "auth_legacy",
    "timeout": 30
}
EOF

    # Create the authentication service script
    cat << 'EOF' > /app/server.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import json

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health' and self.headers.get('X-Legacy-Ping') == 'ping':
            self.send_response(200)
            self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if self.path == '/rotate':
            content_length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(content_length)
            try:
                data = json.loads(body)
                if data.get('legacy_password') == 'SuperSecretLegacy99':
                    self.send_response(200)
                    self.send_header('Content-Type', 'application/json')
                    self.end_headers()
                    self.wfile.write(b'{"new_token": "TOK_abc123_Secure"}')
                    return
            except Exception:
                pass
            self.send_response(400)
            self.end_headers()
        elif self.path == '/audit':
            if self.headers.get('Authorization') == 'Bearer TOK_abc123_Secure':
                self.send_response(200)
                self.end_headers()
            else:
                self.send_response(403)
                self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass

if __name__ == '__main__':
    httpd = HTTPServer(('127.0.0.1', 8342), Handler)
    httpd.serve_forever()
EOF

    # Start the service when the container runs
    echo "python3 /app/server.py > /dev/null 2>&1 &" >> $APPTAINER_ENVIRONMENT
    echo "sleep 0.5" >> $APPTAINER_ENVIRONMENT

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
