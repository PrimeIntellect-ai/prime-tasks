#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server curl
    pip3 install pytest h5py numpy flask redis

    mkdir -p /app/api /app/worker /app/corpora/clean /app/corpora/evil /tmp/uploads

    cat << 'EOF' > /app/api/app.py
import os
from flask import Flask, request
import redis
import uuid

app = Flask(__name__)
r = redis.Redis(host='localhost', port=6379, db=0)

os.makedirs('/tmp/uploads', exist_ok=True)

@app.route('/upload', methods=['POST'])
def upload():
    if 'file' not in request.files:
        return "No file", 400
    file = request.files['file']
    filename = str(uuid.uuid4()) + ".h5"
    filepath = os.path.join('/tmp/uploads', filename)
    file.save(filepath)
    r.lpush('task_queue', filepath)
    return "OK", 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

    cat << 'EOF' > /app/worker/worker.py
import redis
import h5py
import numpy as np
import time

r = redis.Redis(host='localhost', port=6379, db=0)

def process():
    while True:
        task = r.brpop('task_queue', timeout=1)
        if task:
            filepath = task[1].decode('utf-8')
            try:
                with h5py.File(filepath, 'r') as f:
                    X = f['matrix_X'][:]
                inv = np.linalg.inv(X.T @ X)
                r.set(f"result:{filepath}", "SUCCESS")
            except Exception as e:
                r.set(f"result:{filepath}", f"ERROR: {str(e)}")
        time.sleep(0.1)

if __name__ == '__main__':
    process()
EOF

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
nohup python3 /app/api/app.py > /app/api/api.log 2>&1 &
echo $! > /app/api/api.pid
nohup python3 /app/worker/worker.py > /app/worker/worker.log 2>&1 &
echo $! > /app/worker/worker.pid
sleep 2
EOF
    chmod +x /app/start_services.sh

    cat << 'EOF' > /app/stop_services.sh
#!/bin/bash
kill $(cat /app/api/api.pid) || true
kill $(cat /app/worker/worker.pid) || true
redis-cli shutdown || true
EOF
    chmod +x /app/stop_services.sh

    cat << 'EOF' > /app/generate_corpora.py
import os
import h5py
import numpy as np

os.makedirs('/app/corpora/clean', exist_ok=True)
os.makedirs('/app/corpora/evil', exist_ok=True)

for i in range(5):
    with h5py.File(f'/app/corpora/clean/clean_{i}.h5', 'w') as f:
        f.create_dataset('matrix_X', data=np.random.randn(100, 10))

for i in range(5):
    with h5py.File(f'/app/corpora/evil/evil_{i}.h5', 'w') as f:
        X = np.random.randn(100, 10)
        X[:, 1] = X[:, 0] * 2 + np.random.randn(100) * 1e-6
        f.create_dataset('matrix_X', data=X)
EOF
    python3 /app/generate_corpora.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
    chmod -R 777 /tmp/uploads
