#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ruby nodejs
    pip3 install pytest

    mkdir -p /app/vendored/etl-receiver-0.1.0
    cat << 'EOF' > /app/vendored/etl-receiver-0.1.0/Makefile
PORT=80
start:
	python3 server.py --port $(PORT)
EOF

    cat << 'EOF' > /app/vendored/etl-receiver-0.1.0/server.py
import argparse, json, os
from http.server import BaseHTTPRequestHandler, HTTPServer

transactions = {}
AUTH_TOKEN = os.environ.get("AUTH_TOKEN", "default-token")

class RequestHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/api/ingest':
            auth = self.headers.get('Authorization')
            if auth != f"Bearer {AUTH_TOKEN}":
                self.send_response(401)
                self.end_headers()
                return

            txn_id = self.headers.get('Transaction-Id')
            if not txn_id:
                self.send_response(400)
                self.end_headers()
                return

            length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(length)
            data = json.loads(body)

            if txn_id in transactions:
                transactions[txn_id].extend(data)
            else:
                transactions[txn_id] = data

            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"status": "ok", "count": len(transactions[txn_id])}).encode())

    def do_GET(self):
        if self.path == '/api/dump':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(transactions).encode())

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=8000)
    args = parser.parse_args()
    server = HTTPServer(('127.0.0.1', args.port), RequestHandler)
    server.serve_forever()
EOF

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_events.csv
event_id,user_id,text_utf8,lang_code,engagement_score
e1,u1,こんにちは,ja,95.5
e2,u2,ありがとう,ja,80.1
e3,u3,さようなら,ja,80.1
e4,u4,おはよう,ja,12.0
e5,u5,hello,en,40.0
e6,u6,world,en,50.0
e7,u7,test,en,60.0
e8,u8,data,en,70.0
e9,u9,engineering,en,80.0
e10,u10,ai,en,90.0
e11,u11,agent,en,95.0
e12,u12,model,en,99.0
e13,u13,train,en,100.0
e14,u14,validate,en,20.0
e15,u15,test,en,30.0
EOF

    chmod -R 777 /app
    chmod -R 777 /home/user
