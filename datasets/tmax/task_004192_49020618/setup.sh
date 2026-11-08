#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app/legacy_service

    cat << 'EOF' > /app/legacy_service/server.py
import BaseHTTPServer
from router import handle_request

PORT = 8080

class Handler(BaseHTTPServer.BaseHTTPRequestHandler):
    def do_GET(self):
        handle_request(self)

def run():
    server = BaseHTTPServer.HTTPServer(('127.0.0.1', PORT), Handler)
    server.serve_forever()

if __name__ == "__main__":
    run()
EOF

    cat << 'EOF' > /app/legacy_service/router.py
import urlparse
import json
import math_utils

def handle_request(req):
    parsed_path = urlparse.urlparse(req.path)
    if parsed_path.path == '/compute':
        query = urlparse.parse_qs(parsed_path.query)
        if 'text' in query:
            text = query['text'][0]
            # BUG: circular import dependency on PORT from server
            import server
            _ = server.PORT 
            res = math_utils.calculate_hash(text)
            req.send_response(200)
            req.send_header('Content-Type', 'application/json')
            req.end_headers()
            req.wfile.write(json.dumps({"hash": res}))
            return
    req.send_response(404)
    req.end_headers()
EOF

    cat << 'EOF' > /app/legacy_service/math_utils.py
import router # Unnecessary circular import

def calculate_hash(text):
    # BUGGY PYTHON 2 IMPLEMENTATION (fails on UTF-8)
    total = 0
    for i, char in enumerate(text):
        total += ord(char) * (i + 1)
    return total % 1000003
EOF

    cat << 'EOF' > /app/oracle.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    unsigned char *text = (unsigned char *)argv[1];
    long long total = 0;
    for (int i = 0; text[i] != '\0'; i++) {
        total += text[i] * (i + 1);
    }
    printf("%lld\n", total % 1000003);
    return 0;
}
EOF

    gcc /app/oracle.c -o /app/reference_oracle
    strip /app/reference_oracle
    chmod +x /app/reference_oracle
    rm /app/oracle.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
