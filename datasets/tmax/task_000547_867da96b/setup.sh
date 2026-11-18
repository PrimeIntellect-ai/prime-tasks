#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest flask requests

    mkdir -p /app/sim_env

    cat << 'EOF' > /app/sim_env/coordinator.py
from flask import Flask, request, jsonify
import requests

app = Flask(__name__)

def split_mesh(N, k):
    # TODO: Implement this function
    pass

@app.route('/run_sim', methods=['POST'])
def run_sim():
    data = request.json
    N = data.get('N')
    workers = data.get('workers')

    subdomains = split_mesh(N, workers)

    if subdomains is None:
        return jsonify({'error': 'split_mesh not implemented or returned None'}), 500

    results = []
    # Assuming workers are on 5001, 5002, etc.
    for i, (start, end) in enumerate(subdomains):
        port = 5001 + i
        try:
            resp = requests.post(f'http://127.0.0.1:{port}/compute', json={'start': start, 'end': end})
            results.extend(resp.json().get('result', []))
        except Exception as e:
            return jsonify({'error': str(e)}), 500

    return jsonify({'result': results})

if __name__ == '__main__':
    import sys
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 5000
    app.run(port=port)
EOF

    cat << 'EOF' > /app/sim_env/worker.py
from flask import Flask, request, jsonify
import math

app = Flask(__name__)

@app.route('/compute', methods=['POST'])
def compute():
    data = request.json
    start = data.get('start')
    end = data.get('end')

    result = [math.sin(i * 0.1) for i in range(start, end)]
    return jsonify({'result': result})

if __name__ == '__main__':
    import sys
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 5001
    app.run(port=port)
EOF

    cat << 'EOF' > /app/sim_env/data_server.py
import http.server
import socketserver
import os

PORT = 8080
DIRECTORY = "/app/sim_env"

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

with socketserver.TCPServer(("", PORT), Handler) as httpd:
    httpd.serve_forever()
EOF

    python3 -c 'import json, math; json.dump([math.sin(i * 0.1) for i in range(100)], open("/app/sim_env/reference.json", "w"))'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
