#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make libcurl4-openssl-dev libhiredis-dev redis-server curl
    pip3 install pytest

    mkdir -p /home/user/etl_worker
    mkdir -p /app/services

    cat << 'EOF' > /app/services/docker-compose.yml
version: '3'
services:
  upstream:
    image: python:3.9
    command: python3 /app/services/upstream.py
  redis:
    image: redis:latest
EOF

    cat << 'EOF' > /app/services/upstream.py
import http.server
import socketserver
import json
import uuid
import random

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-type", "application/json")
        self.end_headers()
        record = {
            "id": str(uuid.uuid4()),
            "text": "Sample text",
            "category": "A",
            "value": random.random()
        }
        self.wfile.write((json.dumps(record) + "\n").encode())

with socketserver.TCPServer(("127.0.0.1", 8081), Handler) as httpd:
    httpd.serve_forever()
EOF

    cat << 'EOF' > /home/user/etl_worker/worker.c
#include <stdio.h>
int main() {
    printf("Worker\n");
    return 0;
}
EOF

    cat << 'EOF' > /home/user/etl_worker/Makefile
all:
	gcc -o worker worker.c -lcurl -lhiredis
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
