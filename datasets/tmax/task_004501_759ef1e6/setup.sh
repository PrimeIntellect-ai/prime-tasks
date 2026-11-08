#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server curl
    pip3 install pytest flask requests redis

    mkdir -p /home/user/app/corpora/clean
    mkdir -p /home/user/app/corpora/evil
    mkdir -p /home/user/app/gateway
    mkdir -p /home/user/app/dispatcher

    cat << 'EOF' > /home/user/app/corpora/clean/valid1.json
{"repository": "foo", "commit_hash": "abc1234", "build_target": "src/main"}
EOF

    cat << 'EOF' > /home/user/app/corpora/evil/path_traversal.json
{"repository": "foo", "commit_hash": "abc1234", "build_target": "../../../etc/passwd"}
EOF

    cat << 'EOF' > /home/user/app/corpora/evil/missing_fields.json
{"repository": "foo"}
EOF

    python3 -c "print('[' * 2000 + ']' * 2000)" > /home/user/app/corpora/evil/memory_bomb.json

    cat << 'EOF' > /home/user/app/gateway/app.py
from flask import Flask, request, jsonify
import configparser
import redis
import requests
import time

app = Flask(__name__)
config = configparser.ConfigParser()
config.read('config.ini')

try:
    import validator
except ImportError:
    validator = None

r = None
if config.getboolean('DEFAULT', 'RATE_LIMIT_ENABLED', fallback=False):
    r = redis.Redis(host=config.get('DEFAULT', 'REDIS_HOST', fallback='localhost'),
                    port=config.getint('DEFAULT', 'REDIS_PORT', fallback=6379))

@app.route('/webhook', methods=['POST'])
def webhook():
    if r:
        ip = request.remote_addr
        key = f"rate_limit:{ip}"
        current = r.get(key)
        if current and int(current) >= 5:
            return jsonify({"error": "Too Many Requests"}), 429
        r.incr(key)
        r.expire(key, 60)

    if not validator:
        return jsonify({"error": "Validator not implemented"}), 500

    payload_str = request.get_data(as_text=True)
    try:
        is_valid = validator.validate_build_request(payload_str)
    except Exception:
        is_valid = False

    if not is_valid:
        return jsonify({"error": "Invalid payload"}), 400

    dispatcher_url = config.get('DEFAULT', 'DISPATCHER_URL', fallback='')
    if not dispatcher_url:
        return jsonify({"error": "Dispatcher not configured"}), 500

    try:
        resp = requests.post(dispatcher_url, data=payload_str)
        return jsonify({"status": "ok"}), resp.status_code
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(port=5000)
EOF

    cat << 'EOF' > /home/user/app/gateway/config.ini
[DEFAULT]
REDIS_HOST = 
REDIS_PORT = 
DISPATCHER_URL = 
RATE_LIMIT_ENABLED = false
EOF

    cat << 'EOF' > /home/user/app/dispatcher/app.py
from flask import Flask, request, jsonify

app = Flask(__name__)

@app.route('/', defaults={'path': ''}, methods=['POST', 'GET', 'PUT', 'DELETE'])
@app.route('/<path:path>', methods=['POST', 'GET', 'PUT', 'DELETE'])
def catch_all(path):
    return jsonify({"status": "dispatched"}), 200

if __name__ == '__main__':
    app.run(port=5001)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
