#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        redis-server \
        g++ \
        libhiredis-dev \
        nlohmann-json3-dev \
        curl \
        jq

    pip3 install pytest flask redis python-dotenv

    mkdir -p /home/user/app/flask_api
    mkdir -p /home/user/tests/corpora/clean
    mkdir -p /home/user/tests/corpora/evil

    cat << 'EOF' > /home/user/app/flask_api/app.py
import os
import json
from flask import Flask, request, jsonify
import redis
from dotenv import load_dotenv

load_dotenv()

app = Flask(__name__)

redis_host = os.getenv("REDIS_HOST", "127.0.0.1")
redis_port = int(os.getenv("REDIS_PORT", 6379))

r = redis.Redis(host=redis_host, port=redis_port, decode_responses=True)

@app.route('/ingest', methods=['POST'])
def ingest():
    data = request.json
    if not data:
        return jsonify({"error": "Invalid payload"}), 400
    try:
        r.rpush("etl:input", json.dumps(data))
        return jsonify({"status": "queued"}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF

    cat << 'EOF' > /home/user/app/flask_api/.env
REDIS_HOST=invalid.local
REDIS_PORT=9999
EOF

    # Generate clean corpus
    for i in $(seq 1 100); do
        echo "{\"transaction_id\": \"c${i}\", \"user_id\": \"u${i}\", \"amount\": 100.5}" > /home/user/tests/corpora/clean/${i}.json
    done

    # Generate evil corpus
    for i in $(seq 1 10); do
        echo "{\"transaction_id\": \"e${i}\", \"user_id\": \"u${i}\", \"amount\": 9999999.9}" > /home/user/tests/corpora/evil/${i}.json
    done
    for i in $(seq 11 20); do
        echo "{\"transaction_id\": \"e${i}\", \"user_id\": \"u${i}\"}" > /home/user/tests/corpora/evil/${i}.json
    done

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
