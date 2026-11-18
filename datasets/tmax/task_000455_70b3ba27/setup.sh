#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server
    pip3 install pytest flask redis numpy scipy

    mkdir -p /home/user/molecule_sim

    cat << 'EOF' > /home/user/molecule_sim/calc.py
import numpy as np
from scipy.linalg import inv

def solve_steady_state(laplacian):
    # This will fail with LinAlgError if laplacian is singular
    return inv(laplacian)

def compute_diffusion(initial_state):
    # To be implemented
    pass
EOF

    cat << 'EOF' > /home/user/molecule_sim/api.py
from flask import Flask, request, jsonify
import redis
import json

app = Flask(__name__)

@app.route('/simulate', methods=['POST'])
def simulate():
    # To be implemented
    return jsonify({"status": "error", "message": "Not implemented"}), 500

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8080)
EOF

    cat << 'EOF' > /home/user/molecule_sim/redis.conf
bind 127.0.0.1
port 6379
daemonize yes
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
