#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip redis-server nginx sqlite3
pip3 install pytest flask redis python-dateutil

mkdir -p /app
cat << 'EOF' > /app/ingestion.py
from flask import Flask, request
import redis
import json

app = Flask(__name__)
r = redis.Redis(host='127.0.0.1', port=6379, db=0)

@app.route('/ingest', methods=['POST'])
def ingest():
    data = request.get_json()
    r.lpush('raw_data', json.dumps(data))
    return {"status": "ok"}, 200

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5001)
EOF

cat << 'EOF' > /app/query.py
from flask import Flask, request, jsonify
import sqlite3

app = Flask(__name__)

@app.route('/query', methods=['GET'])
def query():
    id_val = request.args.get('id')
    try:
        conn = sqlite3.connect('/home/user/pipeline/clean.db')
        conn.row_factory = sqlite3.Row
        c = conn.cursor()
        c.execute("SELECT * FROM reviews WHERE id = ?", (id_val,))
        row = c.fetchone()
        conn.close()
        if row:
            return jsonify(dict(row))
        return jsonify({"error": "not found"}), 404
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5002)
EOF

cat << 'EOF' > /app/worker.py
import redis
import sqlite3
import json
import time

r = redis.Redis(host='127.0.0.1', port=6379, db=0)

# Connect to DB (fails if dir doesn't exist)
# conn = sqlite3.connect('/home/user/pipeline/clean.db')
# c = conn.cursor()
# c.execute("CREATE TABLE IF NOT EXISTS reviews (id TEXT PRIMARY KEY, timestamp TEXT, review_text TEXT, word_count INTEGER)")
# conn.commit()

while True:
    item = r.rpop('raw_data')
    if item:
        payload = json.loads(item)
        if payload['format'] == 'csv':
            # Buggy implementation splitting by newline
            lines = payload['data'].split('\n')
            for line in lines[1:]:
                if not line.strip(): continue
                parts = line.split(',')
                # ...
        elif payload['format'] == 'json':
            pass
    time.sleep(1)
EOF

useradd -m -s /bin/bash user || true
mkdir -p /home/user/pipeline
chmod -R 777 /home/user
