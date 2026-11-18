#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest scikit-learn pandas fastapi uvicorn requests flask

    mkdir -p /app/services

    cat << 'EOF' > /app/services/start.sh
#!/bin/bash
python3 /app/services/api_a.py &
python3 /app/services/api_b.py &
sleep 2
EOF
    chmod +x /app/services/start.sh

    cat << 'EOF' > /app/services/api_a.py
from http.server import HTTPServer, BaseHTTPRequestHandler
import json

data = [{"user_id": i, "feature_1": i * 0.1, "target": i % 2} for i in range(100)]

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

HTTPServer(('127.0.0.1', 8001), Handler).serve_forever()
EOF

    cat << 'EOF' > /app/services/api_b.py
from http.server import HTTPServer, BaseHTTPRequestHandler
import json

data = [{"user_id": i, "feature_2": i * -0.05} for i in range(100)]

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

HTTPServer(('127.0.0.1', 8002), Handler).serve_forever()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
