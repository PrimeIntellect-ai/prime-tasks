#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip file
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/api_uploads

    cat << 'EOF' > /home/user/server.py
import json
import base64
import os
import hashlib
import subprocess
from http.server import BaseHTTPRequestHandler, HTTPServer

# Blacklist contains the MD5 of a naïve GIF-wrapped payload
BLACKLIST = ["6fa5532d849ab28d11624b516801ca45"] 
# 6fa5532d849ab28d11624b516801ca45 is md5 of b"GIF89aRED_TEAM_STRIKE"

class SimpleAPI(BaseHTTPRequestHandler):
    def _send_response(self, code, body, headers=None):
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        if headers:
            for k, v in headers.items():
                self.send_header(k, v)
        self.end_headers()
        self.wfile.write(json.dumps(body).encode())

    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length)

        try:
            req_data = json.loads(body)
        except json.JSONDecodeError:
            return self._send_response(400, {"error": "Invalid JSON"})

        if self.path == '/login':
            # Authentication flow
            if self.headers.get('X-RedTeam-Auth') == 'viking':
                return self._send_response(200, {"msg": "Success"}, {"Set-Cookie": "session=auth_token_8821"})
            return self._send_response(401, {"error": "Unauthorized"})

        elif self.path == '/upload':
            # Header and Cookie verification
            if 'session=auth_token_8821' not in self.headers.get('Cookie', ''):
                return self._send_response(403, {"error": "Invalid or missing cookie"})

            filename = req_data.get('filename')
            data_b64 = req_data.get('data_b64')

            if not filename or not data_b64:
                return self._send_response(400, {"error": "Missing parameters"})

            try:
                raw_data = base64.b64decode(data_b64)
            except Exception:
                return self._send_response(400, {"error": "Invalid base64 payload"})

            # Cryptographic hash verification (blacklist)
            if hashlib.md5(raw_data).hexdigest() in BLACKLIST:
                return self._send_response(406, {"error": "Payload matches known malware signatures"})

            # Process isolation/Sandboxing verification
            # Writes to tmp, uses system `file` command to verify magic bytes
            tmp_path = f"/tmp/verify_{hashlib.md5(filename.encode()).hexdigest()}"
            with open(tmp_path, 'wb') as f:
                f.write(raw_data)

            try:
                # Isolate validation in a subprocess
                out = subprocess.check_output(['file', '-b', '--mime-type', tmp_path], stderr=subprocess.STDOUT)
                mime = out.decode().strip()
            except subprocess.CalledProcessError:
                os.remove(tmp_path)
                return self._send_response(500, {"error": "Validation process crashed"})

            if not mime.startswith('image/'):
                os.remove(tmp_path)
                return self._send_response(415, {"error": "Only image files are permitted"})

            # Vulnerable file save (Path traversal)
            target_path = os.path.join("/home/user/api_uploads", filename)

            with open(target_path, 'wb') as f:
                f.write(raw_data)

            os.remove(tmp_path)
            return self._send_response(200, {"msg": "File uploaded successfully"})

        return self._send_response(404, {"error": "Not found"})

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 8000), SimpleAPI)
    server.serve_forever()
EOF

    chmod +x /home/user/server.py
    chmod -R 777 /home/user
