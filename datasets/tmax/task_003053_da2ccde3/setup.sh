#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server
    pip3 install --default-timeout=100 pytest fastapi uvicorn redis numpy requests

    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/api.py
import base64
import numpy as np
from fastapi import FastAPI
import redis

app = FastAPI()
r = redis.Redis(host='localhost', port=6379, db=0)

@app.post("/generate")
def generate():
    # Generate random floats between -10 and 10
    data = np.random.uniform(-10, 10, 50).astype('<f4')
    # Serialize
    encoded = base64.b64encode(data.tobytes()).decode('utf-8')
    r.lpush('task_queue', encoded)
    return {"status": "queued"}
EOF

    cat << 'EOF' > /home/user/app/worker.py
import base64
import numpy as np
import redis
import time

r = redis.Redis(host='localhost', port=6379, db=0)

def gradient_descent(data, max_iter=5000, lr=0.01):
    # Dummy gradient descent for geometric median
    estimate = np.mean(data)
    for i in range(max_iter):
        diff = data - estimate
        grad = -np.sum(np.sign(diff))
        if abs(grad) < 1e-3:
            break
        estimate -= lr * grad
    return estimate

def run():
    while True:
        task = r.brpop('task_queue', timeout=1)
        if task:
            _, payload = task
            # BUG: decodes little-endian bytes as big-endian
            data = np.frombuffer(base64.b64decode(payload), dtype='>f4')
            result = gradient_descent(data)
            r.incr('processed_count')

if __name__ == "__main__":
    run()
EOF

    cat << 'EOF' > /home/user/app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
uvicorn api:app --host 0.0.0.0 --port 8000 &
python3 worker.py &
wait
EOF
    chmod +x /home/user/app/start_services.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
