#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/service

    cat << 'EOF' > /home/user/service/requirements.txt
Flask==2.0.1
Werkzeug==2.2.2
pytest==7.0.0
EOF

    cat << 'EOF' > /home/user/service/app.py
from flask import Flask, request, jsonify
from math_utils import collatz_steps

app = Flask(__name__)

@app.route('/collatz/<int:n>')
def get_collatz(n):
    try:
        steps = collatz_steps(n)
        return jsonify({"n": n, "steps": steps})
    except ValueError as e:
        return jsonify({"error": str(e)}), 400

if __name__ == '__main__':
    app.run(port=5000)
EOF

    cat << 'EOF' > /home/user/service/math_utils.py
def collatz_steps(n):
    steps = 0
    while n != 1:
        if n % 2 == 0:
            n = n // 2
        else:
            n = 3 * n + 1
        steps += 1
    return steps
EOF

    chmod -R 777 /home/user
