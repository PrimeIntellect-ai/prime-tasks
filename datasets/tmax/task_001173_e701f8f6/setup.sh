#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ wget curl
    pip3 install pytest

    mkdir -p /home/user/deps
    wget -qO /home/user/deps/httplib.h https://raw.githubusercontent.com/yhirose/cpp-httplib/v0.14.1/httplib.h
    wget -qO /home/user/deps/json.hpp https://raw.githubusercontent.com/nlohmann/json/v3.11.2/single_include/nlohmann/json.hpp

    mkdir -p /app/services

    cat << 'EOF' > /app/services/generate_graph.py
import json
import random

random.seed(42)
nodes = []
types = ['Dataset', 'Paper', 'Author']
for i in range(1, 101):
    nodes.append({'id': i, 'type': random.choice(types)})

edges = []
for _ in range(150):
    u = random.randint(1, 100)
    v = random.randint(1, 100)
    if u != v:
        edges.append([u, v])

with open('/app/services/ground_truth.json', 'w') as f:
    json.dump({'nodes': nodes, 'edges': edges}, f)
EOF

    python3 /app/services/generate_graph.py

    cat << 'EOF' > /app/services/metadata_server.py
import json
from http.server import HTTPServer, BaseHTTPRequestHandler

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/metadata':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            with open('/app/services/ground_truth.json') as f:
                data = json.load(f)
            self.wfile.write(json.dumps(data['nodes']).encode())
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 9001), Handler)
    server.serve_forever()
EOF

    cat << 'EOF' > /app/services/topology_server.py
import socket
import json

def run():
    with open('/app/services/ground_truth.json') as f:
        data = json.load(f)

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(('127.0.0.1', 9002))
    server.listen(5)

    while True:
        client, addr = server.accept()
        for edge in data['edges']:
            client.sendall(f"{edge[0]},{edge[1]}\n".encode())
        client.close()

if __name__ == '__main__':
    run()
EOF

    cat << 'EOF' > /app/services/start_services.sh
#!/bin/bash
python3 /app/services/metadata_server.py &
python3 /app/services/topology_server.py &
echo "Services started"
EOF

    chmod +x /app/services/start_services.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
