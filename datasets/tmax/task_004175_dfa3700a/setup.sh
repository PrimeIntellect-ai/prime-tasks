#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx fcgiwrap curl gawk
    pip3 install --default-timeout=100 pytest numpy flask gunicorn scipy

    mkdir -p /app/data/clean /app/data/evil

    cat << 'EOF' > /app/generate_data.py
import os
import numpy as np

np.random.seed(42)
t = np.linspace(0, 1, 1000)

for i in range(50):
    clean = np.random.normal(0, 1, 1000)
    np.savetxt(f'/app/data/clean/signal_{i}.txt', clean)

    evil = np.random.normal(0, 1, 1000) + 20 * np.sin(2 * np.pi * 400 * t)
    np.savetxt(f'/app/data/evil/signal_{i}.txt', evil)
EOF
    python3 /app/generate_data.py

    cat << 'EOF' > /app/backend.py
from flask import Flask, request

app = Flask(__name__)

@app.route('/factorize', methods=['POST'])
def factorize():
    return "OK\n", 200

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8081)
EOF

    cat << 'EOF' > /app/start.sh
#!/bin/bash
fcgiwrap -s unix:/tmp/fcgiwrap.socket &
sleep 1
chmod 777 /tmp/fcgiwrap.socket
gunicorn -w 1 -b 127.0.0.1:8081 backend:app --chdir /app &
EOF
    chmod +x /app/start.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
