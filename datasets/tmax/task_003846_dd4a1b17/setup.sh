#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx nodejs npm curl
    pip3 install pytest Flask==2.3.2 requests

    mkdir -p /home/user/calc-feature/nodejs-svc
    mkdir -p /home/user/calc-feature/python-svc
    mkdir -p /home/user/calc-feature/nginx_run

    # Python service
    cat << 'EOF' > /home/user/calc-feature/python-svc/app.py
from flask import Flask, jsonify
app = Flask(__name__)

@app.route('/', methods=['GET'])
@app.route('/status', methods=['GET'])
def status():
    return jsonify({"status": "ok", "service": "auth"})

if __name__ == '__main__':
    app.run(port=3002)
EOF

    cat << 'EOF' > /home/user/calc-feature/python-svc/requirements.txt
Flask==2.3.2
EOF

    # Node service
    cat << 'EOF' > /home/user/calc-feature/nodejs-svc/package.json
{
  "name": "calc-svc",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5"
  },
  "peerDependencies": {
    "express": "^3.0.0"
  }
}
EOF

    cat << 'EOF' > /home/user/calc-feature/nodejs-svc/server.js
const express = require('express');
const app = express();
app.use(express.json());

// TODO: Implement parsing and evaluation here
function evaluateExpression(expr) {
    // Agent implements this
    return 0;
}

app.post('/evaluate', (req, res) => {
    const expr = req.body.expression;
    if (!expr) return res.status(400).json({ error: "No expression provided" });
    try {
        const result = evaluateExpression(expr);
        res.json({ result: result });
    } catch (e) {
        res.status(400).json({ error: e.message });
    }
});

app.listen(3001, () => console.log('Node service on 3001'));
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
