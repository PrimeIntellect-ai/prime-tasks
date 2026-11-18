#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-flask python3-redis python3-numpy redis-server curl gcc
    pip3 install pytest

    mkdir -p /app/config /app/corpus/clean /app/corpus/evil /app/eval_corpus/clean /app/eval_corpus/evil /app/src /app/bin

    cat << 'EOF' > /app/config/flask.env
REDIS_URL=redis://localhost:6380
EOF

    cat << 'EOF' > /app/start.sh
#!/bin/bash
# Broken start script
echo "Starting services..."
# redis-server &
# python3 /app/app.py &
# python3 /app/worker.py &
EOF
    chmod +x /app/start.sh

    cat << 'EOF' > /app/app.py
from flask import Flask, request, jsonify
import redis
import os
import json

app = Flask(__name__)
redis_url = os.environ.get("REDIS_URL", "redis://localhost:6379")
r = redis.from_url(redis_url)

@app.route('/process', methods=['POST'])
def process():
    data = request.json
    job_id = r.incr("job_id")
    r.lpush("jobs", json.dumps({"id": job_id, "data_path": data["data_path"]}))
    return jsonify({"job_id": job_id})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

    cat << 'EOF' > /app/worker.py
import redis
import os
import json
import time

redis_url = os.environ.get("REDIS_URL", "redis://localhost:6379")
r = redis.from_url(redis_url)

while True:
    job = r.brpop("jobs", timeout=1)
    if job:
        job_data = json.loads(job[1])
        r.set(f"result_{job_data['id']}", "success")
    time.sleep(0.1)
EOF

    cat << 'EOF' > /tmp/gen_data.py
import os
import numpy as np

def make_clean(path, n):
    for i in range(n):
        x = np.linspace(400, 800, 100)
        y = np.exp(-((x - 600)/50)**2) + np.random.normal(0, 0.05, 100)
        np.savetxt(os.path.join(path, f"clean_{i}.csv"), np.column_stack((x, y)), delimiter=",")

def make_evil(path, n):
    for i in range(n):
        x = np.linspace(400, 800, 100)
        if i % 2 == 0:
            y = np.zeros(100)
        else:
            y = 0.5 * x
        np.savetxt(os.path.join(path, f"evil_{i}.csv"), np.column_stack((x, y)), delimiter=",")

make_clean("/app/corpus/clean", 10)
make_evil("/app/corpus/evil", 10)
make_clean("/app/eval_corpus/clean", 10)
make_evil("/app/eval_corpus/evil", 10)
EOF
    python3 /tmp/gen_data.py
    rm /tmp/gen_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
