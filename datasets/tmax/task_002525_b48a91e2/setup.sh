#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libcurl4-openssl-dev curl wget
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /app/datasets.json
[
  {"id": "ds1", "description": "Global climate and weather patterns"},
  {"id": "ds2", "description": "Financial stock market historical data"},
  {"id": "ds3", "description": "Images of cats and dogs for classification"},
  {"id": "ds4", "description": "Text corpus of ancient Greek literature"},
  {"id": "ds5", "description": "Daily temperature and precipitation records"}
]
EOF

    cat << 'EOF' > /app/metadata_service.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import json

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/datasets':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            with open('/app/datasets.json', 'r') as f:
                self.wfile.write(f.read().encode())

HTTPServer(('127.0.0.1', 8080), Handler).serve_forever()
EOF

    cat << 'EOF' > /app/embedding_service.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import hashlib
import math

def deterministic_embedding(text):
    # Generates a pseudo-random 10-dimensional vector based on MD5 hash
    h = hashlib.md5(text.encode('utf-8')).digest()
    vec = [(b / 255.0) - 0.5 for b in h[:10]]
    norm = math.sqrt(sum(x*x for x in vec))
    return [x/norm for x in vec] if norm > 0 else vec

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/embed':
            length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(length)
            req = json.loads(post_data)
            text = req.get('text', '')

            vec = deterministic_embedding(text)

            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"embedding": vec}).encode())

HTTPServer(('127.0.0.1', 8081), Handler).serve_forever()
EOF

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
python3 /app/metadata_service.py &
python3 /app/embedding_service.py &
sleep 2
EOF
    chmod +x /app/start_services.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
