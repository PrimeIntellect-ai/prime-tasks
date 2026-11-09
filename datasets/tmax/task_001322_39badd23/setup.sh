#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip postgresql redis-server sudo
pip3 install pytest flask psycopg2-binary redis

mkdir -p /home/user/audit_api
mkdir -p /app

cat << 'EOF' > /home/user/audit_api/app.py
from flask import Flask, request, jsonify
import psycopg2
import redis

app = Flask(__name__)

@app.route('/audit', methods=['GET'])
def audit():
    # TODO: Implement this endpoint
    return jsonify({}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF

cat << 'EOF' > /app/oracle_api.py
from flask import Flask, request, jsonify

app = Flask(__name__)

@app.route('/audit', methods=['GET'])
def audit():
    # Mock oracle response for tests
    return jsonify({
        "username": request.args.get('username'),
        "resource_name": request.args.get('resource'),
        "authorized": True,
        "granted_by_roles": ["admin"],
        "recent_access_timestamps": [1690000000.0]
    })

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8081)
EOF

cat << 'EOF' > /app/setup_dbs.py
# Setup script for populating DBs
print("Databases populated")
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
