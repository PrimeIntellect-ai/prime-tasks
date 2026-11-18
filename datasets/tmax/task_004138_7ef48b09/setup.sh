#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server golang
    pip3 install pytest flask redis

    mkdir -p /app/corpus/evil /app/corpus/clean /home/user/output /home/user/worker

    cat << 'EOF' > /app/api.py
from flask import Flask, request
import redis
import json

app = Flask(__name__)
# BUG: wrong port
r = redis.Redis(host='localhost', port=6380, db=0)

@app.route('/ingest', methods=['POST'])
def ingest():
    data = request.json
    filepath = data.get('filepath')
    if filepath:
        r.lpush('processing_queue', filepath)
        return {"status": "queued"}, 200
    return {"error": "no filepath"}, 400

if __name__ == '__main__':
    app.run(port=5000)
EOF

    cat << 'EOF' > /app/labeled_sensor_data.csv
v1,v2,v3,label
1.0,1.0,1.0,0
3.0,0.0,2.0,1
0.0,2.0,0.0,0
4.0,-1.0,1.0,1
2.0,3.0,4.0,0
EOF

    cat << 'EOF' > /app/corpus/clean/test_clean.csv
v1,v2,v3
1.0,1.0,1.0
0.0,2.0,0.0
2.0,3.0,4.0
EOF

    cat << 'EOF' > /app/corpus/evil/test_evil.csv
v1,v2,v3
3.0,0.0,2.0
4.0,-1.0,1.0
5.0,0.0,5.0
EOF

    chmod -R 777 /app
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
