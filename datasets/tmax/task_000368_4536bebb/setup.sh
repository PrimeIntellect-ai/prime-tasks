#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        redis-server \
        redis-tools \
        nginx \
        curl \
        jq \
        nodejs \
        npm

    pip3 install pytest scipy numpy redis flask

    mkdir -p /app/nginx

    npm install --prefix /app express body-parser

    cat << 'EOF' > /app/baseline_singular_values.csv
1.5
2.1
0.8
1.1
1.9
EOF

    cat << 'EOF' > /app/nginx/nginx.conf
# Nginx config template
EOF

    cat << 'EOF' > /app/ingestion_api.py
from flask import Flask, request, jsonify
import redis
import json

app = Flask(__name__)
r = redis.Redis(host='localhost', port=6379, db=0)

@app.route('/ingest', methods=['POST'])
def ingest():
    data = request.json
    if not data:
        return jsonify({"error": "No JSON provided"}), 400
    r.rpush('incoming_matrices', json.dumps(data))
    return jsonify({"status": "queued"}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8001)
EOF

    cat << 'EOF' > /app/webhook_api.js
const express = require('express');
const bodyParser = require('body-parser');

const app = express();
app.use(bodyParser.json());

let metrics = {};

app.post('/report', (req, res) => {
    const auth = req.headers.authorization;
    if (auth !== 'Bearer secret-ml-token') {
        return res.status(401).send('Unauthorized');
    }
    const data = req.body;
    if (data && data.id) {
        metrics[data.id] = data;
    }
    res.status(200).send('OK');
});

app.get('/metrics', (req, res) => {
    res.json(metrics);
});

app.listen(8002, () => {
    console.log('Webhook API listening on port 8002');
});
EOF

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
nohup python3 /app/ingestion_api.py > /app/ingestion.log 2>&1 &
nohup node /app/webhook_api.js > /app/webhook.log 2>&1 &
EOF
    chmod +x /app/start_services.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
