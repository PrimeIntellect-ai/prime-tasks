#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl procps
    pip3 install pytest requests

    useradd -m -s /bin/bash user || true

    # 1. Create the secret token and the target RSA key
    echo -n "FLAG{traversal_identified_992}" > /home/user/secret_token.txt
    echo -n "-----BEGIN PRIVATE KEY-----
MIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQ...
-----END PRIVATE KEY-----" > /home/user/target_rsa
    chmod 777 /home/user/target_rsa

    # 2. Create the traffic log containing the URL encoded payload
    RAW_HTTP="GET /download?file=..%2F..%2F..%2F..%2F..%2Fhome%2Fuser%2Ftarget_rsa HTTP/1.1\r\nHost: 127.0.0.1:8080\r\nUser-Agent: curl/7.68.0\r\nAccept: */*\r\n\r\n"
    echo -n "$RAW_HTTP" | base64 > /home/user/traffic_log.b64

    # 3. Create the vulnerable server script
    cat << 'EOF' > /home/user/server.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import urllib.parse
import os

class VulnHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == '/download':
            qs = urllib.parse.parse_qs(parsed.query)
            if 'file' in qs:
                # Vulnerability: Unquoting and reading without validation
                filepath = urllib.parse.unquote(qs['file'][0])
                try:
                    with open(filepath, 'rb') as f:
                        content = f.read()
                    self.send_response(200)
                    self.end_headers()
                    self.wfile.write(content)
                except Exception as e:
                    self.send_response(404)
                    self.end_headers()
                    self.wfile.write(b"Not found")
            else:
                self.send_response(400)
                self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 8080), VulnHandler)
    server.serve_forever()
EOF

    # 4. Ensure server starts in background when shell is opened
    cat << 'EOF' >> /home/user/.bashrc
if ! pgrep -f "python3 /home/user/server.py" > /dev/null; then
    python3 /home/user/server.py &
fi
EOF
    cat << 'EOF' >> /root/.bashrc
if ! pgrep -f "python3 /home/user/server.py" > /dev/null; then
    python3 /home/user/server.py &
fi
EOF

    chmod -R 777 /home/user
