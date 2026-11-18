#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server curl
    pip3 install pytest flask redis numpy scipy

    mkdir -p /home/user/app
    mkdir -p /home/user/data/clean
    mkdir -p /home/user/data/evil

    cat << 'EOF' > /home/user/app/nginx.conf
events {
    worker_connections 1024;
}
http {
    # TODO: Configure load balancing to Flask instances on ports 5001 and 5002
    # Listen on port 8080
}
EOF

    cat << 'EOF' > /home/user/app/api.py
from flask import Flask
import time
import random
import sys
# import redis

app = Flask(__name__)

@app.route('/ping')
def ping():
    start = time.time()
    time.sleep(random.uniform(0.01, 0.05))
    latency = time.time() - start

    # TODO: Connect to local Redis and lpush latency to 'latency_metrics'

    return "pong"

if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 5000
    app.run(host='127.0.0.1', port=port)
EOF

    cat << 'EOF' > /home/user/app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
nginx -c /home/user/app/nginx.conf
python3 /home/user/app/api.py 5001 > /dev/null 2>&1 &
python3 /home/user/app/api.py 5002 > /dev/null 2>&1 &
echo "Services started."
EOF
    chmod +x /home/user/app/start_services.sh

    # Generate data
    python3 -c "
import os, json, numpy as np
for i in range(50):
    clean_data = np.random.exponential(scale=0.05, size=1000).tolist()
    with open(f'/home/user/data/clean/profile_{i}.json', 'w') as f:
        json.dump(clean_data, f)

    # Evil data: heavy tail / bimodal
    evil_data = np.concatenate([
        np.random.exponential(scale=0.05, size=900),
        np.random.normal(loc=0.5, scale=0.1, size=100)
    ]).tolist()
    np.random.shuffle(evil_data)
    with open(f'/home/user/data/evil/profile_{i}.json', 'w') as f:
        json.dump(evil_data, f)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
