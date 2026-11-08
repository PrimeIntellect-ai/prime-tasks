#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl gawk
    pip3 install pytest flask

    mkdir -p /home/user

    cat << 'EOF' > /home/user/graph_api.py
from flask import Flask, request, jsonify

app = Flask(__name__)

@app.route('/energy', methods=['POST'])
def get_energy():
    data = request.json
    graph_str = data.get('graph', '0'*10)

    # Simple energy function: prefers graphs with exactly 5 edges (e.g. a ring)
    # Energy = absolute difference between number of edges and 5, plus a small penalty for adjacent edges missing
    edges = sum(1 for c in graph_str if c == '1')

    # Ground truth arbitrary energy calculation
    base_energy = abs(edges - 5) * 1.5

    # Add a deterministic pseudo-random structural penalty
    penalty = 0.0
    if graph_str[0] == '1' and graph_str[9] == '1':
        penalty -= 0.5
    if graph_str[1:4] == '000':
        penalty += 1.2

    energy = base_energy + penalty + 1.0
    return jsonify({"energy": round(energy, 4)})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8000)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
