#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl nginx redis-server
    pip3 install pytest h5py numpy flask fastapi uvicorn python-dotenv redis

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data/clean
    mkdir -p /home/user/data/evil
    mkdir -p /home/user/config

    cat << 'EOF' > /home/user/generate_data.py
import h5py
import numpy as np
import os

# Generate clean HDF5 (largest singular value < 10)
for i in range(5):
    with h5py.File(f'/home/user/data/clean/seq_{i}.h5', 'w') as f:
        # Create a matrix with small random values, max singular value around 3-5
        mat = np.random.rand(50, 50) * 0.1 
        f.create_dataset('/quality_scores', data=mat)

# Generate evil HDF5 (largest singular value > 15)
for i in range(5):
    with h5py.File(f'/home/user/data/evil/poison_{i}.h5', 'w') as f:
        # Create a matrix with a large dominant component
        mat = np.random.rand(50, 50)
        # Artificially boost the first singular component
        u, s, vh = np.linalg.svd(mat)
        s[0] = 20.0
        mat_evil = np.dot(u * s, vh)
        f.create_dataset('/quality_scores', data=mat_evil)
EOF

    python3 /home/user/generate_data.py
    rm /home/user/generate_data.py

    cat << 'EOF' > /home/user/config/nginx.conf
events {}
http {
    server {
        listen 8080;
        location /api/upload {
            proxy_pass http://localhost:9999; # WRONG PORT
        }
        location /api/align {
            proxy_pass http://localhost:9998; # WRONG PORT
        }
    }
}
EOF

    cat << 'EOF' > /home/user/config/.env
REDIS_PORT=6380
EOF

    cat << 'EOF' > /home/user/ingestion.py
from flask import Flask, request
import os
import redis
from dotenv import load_dotenv

load_dotenv('/home/user/config/.env')
app = Flask(__name__)
r = redis.Redis(host='localhost', port=int(os.getenv('REDIS_PORT', 6379)))

@app.route('/api/upload', methods=['POST'])
def upload():
    r.ping()
    return "OK", 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

    cat << 'EOF' > /home/user/alignment.py
from fastapi import FastAPI
import os
import redis
from dotenv import load_dotenv

load_dotenv('/home/user/config/.env')
app = FastAPI()
r = redis.Redis(host='localhost', port=int(os.getenv('REDIS_PORT', 6379)))

@app.get('/api/align/status')
def status():
    r.ping()
    return {"status": "listening"}
EOF

    cat << 'EOF' > /home/user/start_services.sh
#!/bin/bash
redis-server --daemonize yes
nginx -c /home/user/config/nginx.conf
python3 /home/user/ingestion.py &
uvicorn alignment:app --host 0.0.0.0 --port 5001 --app-dir /home/user &
sleep 2
EOF
    chmod +x /home/user/start_services.sh

    chmod -R 777 /home/user
