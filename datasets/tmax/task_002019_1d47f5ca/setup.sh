#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server parallel gawk bc curl
    pip3 install pytest flask redis numpy

    mkdir -p /app/pipeline /app/corpus/clean /app/corpus/evil

    # Generate corpus files
    cat << 'EOF' > /tmp/gen_data.py
import numpy as np
import os

np.random.seed(42)

for i in range(1, 51):
    clean_data = np.random.normal(50, 5, 1000)
    evil_data = np.random.normal(55, 5, 1000)

    np.savetxt(f"/app/corpus/clean/clean_{i:02d}.txt", clean_data, fmt="%.6f")
    np.savetxt(f"/app/corpus/evil/evil_{i:02d}.txt", evil_data, fmt="%.6f")
EOF
    python3 /tmp/gen_data.py
    rm /tmp/gen_data.py

    # Create broken api.py
    cat << 'EOF' > /app/pipeline/api.py
from flask import Flask, request
import redis

app = Flask(__name__)
r = redis.Redis(host='10.0.0.5', port=9999)

@app.route('/ingest', methods=['POST'])
def ingest():
    path = request.get_data(as_text=True)
    r.rpush('task_queue', path)
    return "OK"

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8080)
EOF

    # Create broken worker.sh
    cat << 'EOF' > /app/pipeline/worker.sh
#!/bin/bash
while true; do
    task=$(redis-cli LPOP wrong_queue)
    if [ -n "$task" ]; then
        /app/filter.sh "$task"
    fi
    sleep 1
done
EOF
    chmod +x /app/pipeline/worker.sh

    # Create broken redis configuration
    mkdir -p /etc/redis
    echo "port 0" > /etc/redis/redis.conf

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app /etc/redis
