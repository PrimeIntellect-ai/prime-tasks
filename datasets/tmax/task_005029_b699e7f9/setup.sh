#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/server.py
import json
import base64
from http.server import BaseHTTPRequestHandler, HTTPServer

class BuildRequestHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        post_data = self.rfile.read(content_length)
        data = json.loads(post_data)

        b64_config = data.get("config", "")
        config_str = base64.b64decode(b64_config).decode('utf-8')

        if config_str.startswith("target_app="):
            target = config_str.split("=")[1]
            with open("/home/user/config.mk", "w") as f:
                f.write(f"TARGET := {target}\n")

            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"Success")
        else:
            self.send_response(400)
            self.end_headers()
            self.wfile.write(b"Bad Request")

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 8080), BuildRequestHandler)
    server.serve_forever()
EOF

chmod -R 777 /home/user
