#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip socat
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/microservices/logs

    cat << 'EOF' > /home/user/microservices/config.ini
[Emitter]
processor_host = 127.0.0.1
processor_port = 8080

[Processor]
aggregator_host = 127.0.0.1
aggregator_port = 9003

[Aggregator]
listen_host = 127.0.0.1
listen_port = 8003
EOF

    cat << 'EOF' > /home/user/microservices/emitter.py
#!/usr/bin/env python3
import time, urllib.request, configparser, uuid, json

config = configparser.ConfigParser()
config.read('config.ini')
host = config['Emitter']['processor_host']
port = config['Emitter']['processor_port']

while True:
    try:
        req = urllib.request.Request(f"http://{host}:{port}/process", method="POST")
        req.add_header('Content-Type', 'application/json')
        data = json.dumps({"tid": str(uuid.uuid4())}).encode('utf-8')
        with urllib.request.urlopen(req, data=data, timeout=1) as response:
            pass
    except Exception as e:
        with open('logs/emitter.log', 'a') as f:
            f.write(f"Error: {e}\n")
    time.sleep(1)
EOF

    cat << 'EOF' > /home/user/microservices/processor.py
#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, HTTPServer
import urllib.request, configparser, json

config = configparser.ConfigParser()
config.read('config.ini')
agg_host = config['Processor']['aggregator_host']
agg_port = config['Processor']['aggregator_port']

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/process':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            try:
                req = urllib.request.Request(f"http://{agg_host}:{agg_port}/aggregate", method="POST")
                req.add_header('Content-Type', 'application/json')
                with urllib.request.urlopen(req, data=post_data, timeout=1) as response:
                    self.send_response(200)
                    self.end_headers()
            except Exception as e:
                self.send_response(500)
                self.end_headers()
                with open('logs/processor.log', 'a') as f:
                    f.write(f"Forward error: {e}\n")

server = HTTPServer(('127.0.0.1', 8002), Handler)
server.serve_forever()
EOF

    cat << 'EOF' > /home/user/microservices/aggregator.py
#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, HTTPServer
import json, configparser

config = configparser.ConfigParser()
config.read('config.ini')
port = int(config['Aggregator']['listen_port'])
total = 0

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        global total
        if self.path == '/aggregate':
            content_length = int(self.headers['Content-Length'])
            post_data = json.loads(self.rfile.read(content_length))
            total += 1
            with open('logs/aggregator.log', 'a') as f:
                f.write(f"[INFO] - SUCCESS - Transaction ID: {post_data.get('tid', 'unknown')} - Payload processed\n")
            self.send_response(200)
            self.end_headers()

    def do_GET(self):
        if self.path == '/stats':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"total_received": total}).encode())

server = HTTPServer(('127.0.0.1', port), Handler)
server.serve_forever()
EOF

    chmod +x /home/user/microservices/*.py
    chmod -R 777 /home/user
