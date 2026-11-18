#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tzdata
pip3 install pytest

mkdir -p /home/user/corpus/clean /home/user/corpus/evil

# Clean corpus
echo "/api/v1/status" > /home/user/corpus/clean/1.txt
echo "/user/123/profile" > /home/user/corpus/clean/2.txt
echo "/search?q=hello+world" > /home/user/corpus/clean/3.txt

# Evil corpus
echo "/api/v1/status?q=UNION+SELECT+*+FROM+users" > /home/user/corpus/evil/1.txt
echo "/user/../../../etc/passwd" > /home/user/corpus/evil/2.txt
echo "/search?q=<ScRiPt>alert(1)</script>" > /home/user/corpus/evil/3.txt
echo "/execute?cmd=eval(base64_decode('...'))" > /home/user/corpus/evil/4.txt

# Backend service script
cat << 'EOF' > /home/user/backend.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import sys

port = int(sys.argv[1])

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'text/plain')
        self.end_headers()
        proxy_time = self.headers.get('X-Proxy-Time', 'MISSING')
        self.wfile.write(f"Backend {port} - Time: {proxy_time}".encode())

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', port), Handler)
    server.serve_forever()
EOF

useradd -m -s /bin/bash user || true

# Start backends on shell login
echo "python3 /home/user/backend.py 8081 &" >> /home/user/.bashrc
echo "python3 /home/user/backend.py 8082 &" >> /home/user/.bashrc
echo "python3 /home/user/backend.py 8081 &" >> /root/.bashrc
echo "python3 /home/user/backend.py 8082 &" >> /root/.bashrc

chmod -R 777 /home/user
