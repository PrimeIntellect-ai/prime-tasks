#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git curl jq socat cron
    pip3 install pytest

    mkdir -p /app/test_corpus/clean /app/test_corpus/evil

    cat << 'EOF' > /app/test_corpus/evil/bad_rate.json
{"id": 1, "refresh_rate": "1s", "datasource": "dev"}
EOF
    cat << 'EOF' > /app/test_corpus/evil/bad_db.json
{"id": 2, "refresh_rate": "1m", "datasource": "production", "mode": "write"}
EOF

    cat << 'EOF' > /app/test_corpus/clean/good1.json
{"id": 3, "refresh_rate": "30s", "datasource": "dev"}
EOF
    cat << 'EOF' > /app/test_corpus/clean/good2.json
{"id": 4, "refresh_rate": "1m", "datasource": "production", "mode": "read-only"}
EOF

    cat << 'EOF' > /app/api.py
from http.server import BaseHTTPRequestHandler, HTTPServer
class S(BaseHTTPRequestHandler):
    def do_POST(self):
        self.send_response(200)
        self.end_headers()
        with open('/app/uploaded.log', 'a') as f:
            f.write('success\n')
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
HTTPServer(('127.0.0.1', 9090), S).serve_forever()
EOF

    touch /app/uploaded.log
    chmod 666 /app/uploaded.log

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
