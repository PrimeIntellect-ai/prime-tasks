#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server nginx curl gawk
    pip3 install pytest flask redis python-dotenv

    mkdir -p /app/corpus/evil /app/corpus/clean /app/data /app/api

    # Create Flask API
    cat << 'EOF' > /app/api/app.py
import os
from flask import Flask, request, jsonify
from dotenv import load_dotenv

load_dotenv('/app/api/.env')
app = Flask(__name__)

@app.route('/score', methods=['GET'])
def score():
    text = request.args.get('text', '').lower()
    if 'leak' in text or 'poison' in text:
        return jsonify({"status": "evil"})
    return jsonify({"status": "clean"})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    # Create env file with misconfiguration
    cat << 'EOF' > /app/api/.env
REDIS_PORT=6378
EOF

    # Create Nginx misconfiguration
    rm -f /etc/nginx/sites-enabled/default
    cat << 'EOF' > /etc/nginx/conf.d/api.conf
server {
    listen 8080;
    location /score {
        proxy_pass http://127.0.0.1:5001;
    }
}
EOF

    # Create embeddings
    cat << 'EOF' > /app/data/embeddings.csv
id,cluster_id
101,c_44
102,c_99
103,c_10
104,c_11
EOF

    # Create corpus
    cat << 'EOF' > /app/corpus/evil/leak1.csv
id,text_data
102,this is a leak
EOF
    cat << 'EOF' > /app/corpus/evil/poison2.csv
id,text_data
104,this is poison
EOF

    cat << 'EOF' > /app/corpus/clean/valid1.csv
id,text_data
101,this is a sample row
EOF
    cat << 'EOF' > /app/corpus/clean/valid2.csv
id,text_data
103,this is another clean row
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
