#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server curl
    pip3 install pytest flask redis scipy numpy pandas

    mkdir -p /app/nanopore_pipeline

    cat << 'EOF' > /app/nanopore_pipeline/streamer.py
import json
from flask import Flask, jsonify
import numpy as np
import redis
import threading
import time

app = Flask(__name__)

def populate_redis():
    time.sleep(2)
    try:
        r = redis.Redis(host='127.0.0.1', port=6379)
        r.delete('jobs')
        for i in range(100):
            r.rpush('jobs', str(i))
    except:
        pass

threading.Thread(target=populate_redis, daemon=True).start()

def generate_signal(event_id):
    np.random.seed(int(event_id))
    c = np.random.uniform(0.2, 0.8)
    x = np.linspace(0, 1, 10000)
    y = 100 * np.exp(-10000 * (x - c)**2)
    return x.tolist(), y.tolist()

@app.route('/signal/<event_id>')
def get_signal(event_id):
    x, y = generate_signal(event_id)
    return jsonify({"x": x, "y": y})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    cat << 'EOF' > /app/nanopore_pipeline/worker.sh
#!/bin/bash
source /app/nanopore_pipeline/.env

while true; do
    job_id=$(redis-cli -p $REDIS_PORT lpop jobs)
    if [ -z "$job_id" ]; then
        break
    fi
    curl -s http://127.0.0.1:5050/signal/$job_id | python3 /app/nanopore_pipeline/integrate.py $job_id >> /home/user/results.csv
done
EOF
    chmod +x /app/nanopore_pipeline/worker.sh

    cat << 'EOF' > /app/nanopore_pipeline/integrate.py
import sys
import json

def main():
    if len(sys.argv) < 2:
        sys.exit(1)
    event_id = sys.argv[1]
    try:
        data = json.loads(sys.stdin.read())
        x = data['x']
        y = data['y']

        step = 100
        integral = 0
        for i in range(0, len(x)-step, step):
            dx = x[i+step] - x[i]
            integral += y[i] * dx

        print(f"{event_id},{integral}")
    except Exception as e:
        pass

if __name__ == "__main__":
    main()
EOF

    cat << 'EOF' > /app/nanopore_pipeline/.env
REDIS_PORT=6380
EOF

    cat << 'EOF' > /tmp/generate_gt.py
import numpy as np
import scipy.integrate as integrate
import csv

with open('/app/nanopore_pipeline/ground_truth.csv', 'w') as f:
    writer = csv.writer(f)
    for i in range(100):
        np.random.seed(i)
        c = np.random.uniform(0.2, 0.8)
        val, _ = integrate.quad(lambda x: 100 * np.exp(-10000 * (x - c)**2), 0, 1)
        writer.writerow([i, val])
EOF
    python3 /tmp/generate_gt.py
    rm /tmp/generate_gt.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app/nanopore_pipeline
    chmod -R 777 /home/user
