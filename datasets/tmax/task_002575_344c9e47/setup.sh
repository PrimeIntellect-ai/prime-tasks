#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx jq curl
    pip3 install pytest flask

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Create Flask app
    cat << 'EOF' > /app/app.py
from flask import Flask, request, jsonify
app = Flask(__name__)

@app.route('/api', methods=['GET', 'POST'])
def api():
    return jsonify(dict(request.headers)), 200

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    # Create Nginx config
    cat << 'EOF' > /app/nginx.conf
worker_processes 1;
events {
    worker_connections 1024;
}
http {
    server {
        listen 8080;
        location / {
            proxy_pass http://127.0.0.1:5000;
            # Intentionally strip the Authorization header
            proxy_set_header Authorization "";
        }
    }
}
EOF

    # Populate corpus
    # Clean 1: HS256
    echo -n "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.e30.signature" > /app/corpus/clean/1.txt
    # Clean 2: RS256
    echo -n "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.e30.signature" > /app/corpus/clean/2.txt

    # Evil 1: alg none
    echo -n "eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.e30.signature" > /app/corpus/evil/1.txt
    # Evil 2: alg NoNe
    echo -n "eyJhbGciOiJOb05lIiwidHlwIjoiSldUIn0.e30.signature" > /app/corpus/evil/2.txt
    # Evil 3: missing signature
    echo -n "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.e30." > /app/corpus/evil/3.txt
    # Evil 4: only two parts
    echo -n "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.e30" > /app/corpus/evil/4.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
