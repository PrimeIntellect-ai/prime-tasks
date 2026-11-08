#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest flask fastapi uvicorn requests networkx

    mkdir -p /app

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
python3 /app/service_edges.py &
python3 /app/service_nodes.py &
sleep 2
EOF
    chmod +x /app/start_services.sh

    cat << 'EOF' > /app/service_edges.py
from http.server import HTTPServer, BaseHTTPRequestHandler
import json

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/edges':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            data = [
                {"waiter": "T1", "holder": "T2"},
                {"waiter": "T2", "holder": "T3"},
                {"waiter": "T3", "holder": "T1"},
                {"waiter": "T3", "holder": "T4"},
                {"waiter": "T4", "holder": "T5"},
                {"waiter": "T5", "holder": "T6"},
                {"waiter": "T6", "holder": "T4"},
                {"waiter": "T7", "holder": "T8"},
                {"waiter": "T8", "holder": "T7"}
            ]
            self.wfile.write(json.dumps(data).encode())

HTTPServer(('127.0.0.1', 9001), Handler).serve_forever()
EOF

    cat << 'EOF' > /app/service_nodes.py
from http.server import HTTPServer, BaseHTTPRequestHandler
import json

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/nodes':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            data = [
                {"tx_id": "T1", "user": "alice"},
                {"tx_id": "T2", "user": "bob"},
                {"tx_id": "T3", "user": "charlie"},
                {"tx_id": "T4", "user": "dave"},
                {"tx_id": "T5", "user": "eve"},
                {"tx_id": "T6", "user": "frank"},
                {"tx_id": "T7", "user": "grace"},
                {"tx_id": "T8", "user": "heidi"}
            ]
            self.wfile.write(json.dumps(data).encode())

HTTPServer(('127.0.0.1', 9002), Handler).serve_forever()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
