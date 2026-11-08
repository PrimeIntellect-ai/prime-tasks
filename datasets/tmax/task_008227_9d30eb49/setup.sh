#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential rustc cargo
    pip3 install pytest flask

    mkdir -p /home/user/service /home/user/data

    cat << 'EOF' > /home/user/service/embed_app.py
from flask import Flask, request, jsonify

app = Flask(__name__)

# Deterministic dummy embeddings based on string length and first char for reproducibility
@app.route('/embed', methods=['POST'])
def embed():
    data = request.json
    text = data.get('text', '')
    length = len(text)

    if text.startswith('ERROR'):
        # Creates a large embedding that will project to X=25, Y=25 (Distance > 15)
        vec = [5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0, 5.0]
    elif text.startswith('WARN'):
        # Creates an embedding that projects to X=10, Y=10 (Distance ~ 14.14 <= 15)
        vec = [2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0]
    elif text.startswith('CRITICAL'):
        # Creates a large embedding that projects to X=40, Y=0 (Distance = 40 > 15)
        vec = [8.0, 8.0, 8.0, 8.0, 8.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    else:
        # INFO logs project to X=5, Y=5 (Distance ~ 7.07 <= 15)
        vec = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]

    return jsonify({"embedding": vec})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8080)
EOF

    cat << 'EOF' > /home/user/data/logs.csv
id,text
1,INFO System started successfully
2,WARN High memory usage detected
3,ERROR Failed to connect to database
4,INFO User login successful
5,CRITICAL Kernel panic
6,INFO Background job finished
7,ERROR Timeout while calling external API
8,WARN Disk space running low
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
