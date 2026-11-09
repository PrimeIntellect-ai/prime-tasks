#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server git curl jq
    pip3 install pytest numpy flask redis

    mkdir -p /app/anomaly_pipeline
    cd /app/anomaly_pipeline

    cat << 'EOF' > config.json
{
    "redis_port": 6380,
    "redis_host": "127.0.0.1"
}
EOF

    cat << 'EOF' > start_services.sh
#!/bin/bash
redis-server --daemonize yes --port 6379
cd /app/anomaly_pipeline
nohup python3 api_gateway.py > api.log 2>&1 &
cd /app/anomaly_pipeline/worker_repo
nohup python3 worker.py > worker.log 2>&1 &
EOF
    chmod +x start_services.sh

    cat << 'EOF' > restart_all.sh
#!/bin/bash
pkill -f redis-server
pkill -f api_gateway.py
pkill -f worker.py
sleep 1
/app/anomaly_pipeline/start_services.sh
EOF
    chmod +x restart_all.sh

    cat << 'EOF' > api_gateway.py
from flask import Flask, request, jsonify
import redis
import json

app = Flask(__name__)
with open('/app/anomaly_pipeline/config.json') as f:
    config = json.load(f)
r = redis.Redis(host=config['redis_host'], port=config['redis_port'])

@app.route('/api/v1/analyze', methods=['POST'])
def analyze():
    auth = request.headers.get('Authorization')
    if auth != 'Bearer IT-SUPPORT-AUTH-992':
        return jsonify({"error": "Unauthorized"}), 401

    data = request.json
    series_id = data.get('series_id')

    r.rpush('task_queue', series_id)

    import time
    for _ in range(50):
        res = r.get(f'result_{series_id}')
        if res:
            return jsonify(json.loads(res))
        time.sleep(0.1)

    return jsonify({"error": "timeout"}), 500

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8080)
EOF

    mkdir worker_repo
    cd worker_repo
    git init
    git config user.email "admin@example.com"
    git config user.name "Admin"

    cat << 'EOF' > worker.py
import redis
import json
import time
from compute_engine import compute_variance

with open('/app/anomaly_pipeline/config.json') as f:
    config = json.load(f)
r = redis.Redis(host=config['redis_host'], port=config['redis_port'])

while True:
    task = r.lpop('task_queue')
    if task:
        series_id = task.decode('utf-8')
        variance = compute_variance()
        status = "converged" if variance > 1.5 else "failed"
        r.set(f'result_{series_id}', json.dumps({"status": status, "variance": variance}))
    time.sleep(0.1)
EOF

    cat << 'EOF' > compute_engine.py
import numpy as np

def compute_variance():
    val = np.float64(1.0)
    for _ in range(1000):
        val += np.float64(0.001)
    return float(val)
EOF

    cat << 'EOF' > test_convergence.py
import sys
from compute_engine import compute_variance

if __name__ == '__main__':
    v = compute_variance()
    if v > 1.5:
        sys.exit(0)
    else:
        sys.exit(1)
EOF

    git add .
    git commit -m "Initial commit"
    git tag v1.0

    for i in 1 2 3; do
        echo "# comment $i" >> compute_engine.py
        git add compute_engine.py
        git commit -m "Good commit $i"
    done

    cat << 'EOF' > compute_engine.py
import numpy as np

def compute_variance():
    val = np.float32(1.0)
    for _ in range(10):
        val += np.float32(0.001)
    return float(val)
EOF
    git add compute_engine.py
    git commit -m "Optimize compute engine"
    git rev-parse HEAD > /app/anomaly_pipeline/.secret_bad_commit

    for i in 1 2 3; do
        echo "# comment bad $i" >> compute_engine.py
        git add compute_engine.py
        git commit -m "Bad commit $i"
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
