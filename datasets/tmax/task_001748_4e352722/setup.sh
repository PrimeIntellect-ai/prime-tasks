#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest requests

    mkdir -p /app/fast-csv-api
    cd /app/fast-csv-api
    git init
    git config user.email "test@example.com"
    git config user.name "Test User"

    cat << 'EOF' > server.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
from processor import process_data

class RequestHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/process':
            content_length = int(self.headers.get('Content-Length', 0))
            post_data = self.rfile.read(content_length).decode('utf-8')
            try:
                res = process_data(post_data)
                self.send_response(200)
                self.end_headers()
                self.wfile.write(json.dumps({"status": "success", "rows": len(res)}).encode())
            except Exception as e:
                self.send_response(400)
                self.end_headers()
                self.wfile.write(b"Error")

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 8080), RequestHandler)
    server.serve_forever()
EOF

    cat << 'EOF' > processor.py
def process_data(data):
    rows = []
    for line in data.split('\n'):
        line = line.strip()
        if not line: continue

        idx = 0
        while idx < len(line):
            if line[idx] == '"':
                next_quote = line.find('"', idx + 1)
                if next_quote == -1:
                    break
                idx = next_quote + 1
            else:
                idx += 1
        rows.append(line.split(','))
    return rows
EOF

    git add .
    git commit -m "Initial commit: working CSV processor"

    cat << 'EOF' > processor.py
def process_data(data):
    rows = []
    for line in data.split('\n'):
        line = line.strip()
        if not line: continue

        idx = 0
        while idx < len(line):
            if line[idx] == '"':
                next_quote = line.find('"', idx + 1)
                if next_quote == -1:
                    # BUG: missing break/idx increment, causes infinite loop on unclosed quote
                    continue
                idx = next_quote + 1
            else:
                idx += 1
        rows.append(line.split(','))
    return rows
EOF

    git add processor.py
    git commit -m "Refactor: change unclosed quote handling"

    mkdir -p /home/user
    cat << 'EOF' > /home/user/bad_input.csv
id,name,value
1,alice,100
2,bob,200
3,"charlie,300
4,david,400
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
