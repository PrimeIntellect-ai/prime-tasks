#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nodejs socat tar curl
    pip3 install pytest flask

    mkdir -p /home/user/app
    mkdir -p /home/user/backups

    # Create backup archive contents
    mkdir -p /tmp/backup_prep
    cat << 'EOF' > /tmp/backup_prep/config.json
{"db_port": 6055, "api_port": 5001}
EOF

    cat << 'EOF' > /tmp/backup_prep/data.db
{"records": 100, "state": "ready"}
EOF

    tar -czf /home/user/backups/app_backup.tar.gz -C /tmp/backup_prep config.json data.db
    rm -rf /tmp/backup_prep

    # Create Python API script
    cat << 'EOF' > /home/user/app/api.py
import os
import json
import socket
from flask import Flask, jsonify

app = Flask(__name__)

@app.route('/api/status', methods=['GET'])
def status():
    try:
        with open('/home/user/app/config.json', 'r') as f:
            config = json.load(f)
        db_port = config.get('db_port', 9999)

        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(2)
        s.connect(('127.0.0.1', db_port))
        s.sendall(b'PING\n')
        data = s.recv(1024).decode('utf-8')
        s.close()

        if 'PONG: DATA_READY' in data:
            return jsonify({"status": "ok", "db_connected": True}), 200
        else:
            return jsonify({"status": "error", "db_connected": False}), 500
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5001)
EOF

    # Create Node.js data service script
    cat << 'EOF' > /home/user/app/data_service.js
const net = require('net');
const fs = require('fs');

const DB_FILE = '/home/user/app/data.db';
const PORT = 9999;

if (!fs.existsSync(DB_FILE)) {
    console.error('CRITICAL: data.db not found! Crashing...');
    process.exit(1);
}

const server = net.createServer((socket) => {
    socket.on('data', (data) => {
        if (data.toString().trim() === 'PING') {
            socket.write('PONG: DATA_READY\n');
        }
    });
});

server.listen(PORT, '127.0.0.1', () => {
    console.log(`Data service listening on 127.0.0.1:${PORT}`);
});
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
