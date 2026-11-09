#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server hdf5-tools jq curl gawk bc sed
    pip3 install pytest flask redis h5py numpy

    mkdir -p /app/api

    cat << 'EOF' > /app/api/config.ini
[DEFAULT]
CACHE_HOST=redis-db
CACHE_PORT=6379
EOF

    cat << 'EOF' > /app/api/server.py
from flask import Flask, jsonify
import redis
import configparser

app = Flask(__name__)
config = configparser.ConfigParser()
config.read('/app/api/config.ini')

cache = redis.Redis(
    host=config['DEFAULT'].get('CACHE_HOST', 'localhost'),
    port=int(config['DEFAULT'].get('CACHE_PORT', 6379))
)

@app.route('/api/v1/sequences')
def get_sequences():
    try:
        cache.ping()
        return jsonify(["seq1", "seq2"])
    except:
        return "Redis not reachable", 500

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8000)
EOF

    cat << 'EOF' > /app/ground_truth.csv
Sequence_ID,Alignment_Score
seq1,12.5
seq2,8.4
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
