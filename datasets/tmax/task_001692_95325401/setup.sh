#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server curl rustc cargo
    pip3 install pytest

    mkdir -p /app/staging/nginx
    mkdir -p /app/staging/redis
    mkdir -p /app/staging/backend
    mkdir -p /app/evidence/samples
    mkdir -p /app/verifier/corpus/evil
    mkdir -p /app/verifier/corpus/clean

    # Broken Nginx config
    cat << 'EOF' > /app/staging/nginx/nginx.conf
events {}
http {
    server {
        listen 8080;
        location /api/ {
            # proxy_pass missing
            return 404;
        }
    }
}
EOF

    # Redis config
    cat << 'EOF' > /app/staging/redis/redis.conf
port 6379
daemonize no
EOF

    # Backend API Server
    cat << 'EOF' > /app/staging/backend/api_server
#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, HTTPServer
import socket
import json

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/api/health':
            try:
                s = socket.socket()
                s.connect(('127.0.0.1', 6379))
                s.close()
                res = {"status": "ok", "redis": "connected"}
            except Exception as e:
                res = {"status": "error", "redis": "disconnected"}
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(res).encode())
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    print("Starting API Server on 127.0.0.1:8081")
    HTTPServer(('127.0.0.1', 8081), Handler).serve_forever()
EOF
    chmod +x /app/staging/backend/api_server

    # Evidence log
    cat << 'EOF' > /app/evidence/backdoor_requests.log
GET /api/system_exec HTTP/1.1
Host: 127.0.0.1:8080
X-Backdoor-Auth: 4d284bc783c5a611f71a938c6bf65609
EOF

    # Evil Corpus
    cat << 'EOF' > /app/verifier/corpus/evil/evil1.txt
GET /api/system_exec HTTP/1.1
X-Backdoor-Auth: 4d284bc783c5a611f71a938c6bf65609
EOF
    cat << 'EOF' > /app/verifier/corpus/evil/evil2.txt
POST /api/login HTTP/1.1
Content-Type: application/json

{"user": "' OR '1'='1"}
EOF
    cat << 'EOF' > /app/verifier/corpus/evil/evil3.txt
POST /api/comments HTTP/1.1
Content-Type: application/json

{"comment": "<script>alert(1)</script>"}
EOF

    # Clean Corpus
    cat << 'EOF' > /app/verifier/corpus/clean/clean1.txt
GET /api/health HTTP/1.1
Host: 127.0.0.1:8080
EOF
    cat << 'EOF' > /app/verifier/corpus/clean/clean2.txt
POST /api/login HTTP/1.1
Content-Type: application/json

{"user": "alice", "pass": "secret"}
EOF

    # Samples
    cp /app/verifier/corpus/evil/evil1.txt /app/evidence/samples/sample_evil.txt
    cp /app/verifier/corpus/clean/clean1.txt /app/evidence/samples/sample_clean.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
