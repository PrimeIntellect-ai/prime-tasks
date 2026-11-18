#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip nginx redis-server
pip3 install pytest flask redis pandas numpy scikit-learn

mkdir -p /home/user/app /home/user/data/clean /home/user/data/evil

cat << 'EOF' > /tmp/generate_clean.py
import pandas as pd
import numpy as np
import os
np.random.seed(42)
os.makedirs('/home/user/data/clean/', exist_ok=True)
for i in range(10):
    # 5 features, random noise, low correlation
    df = pd.DataFrame(np.random.randn(100, 5), columns=[f'sensor_{j}' for j in range(5)])
    df.to_csv(f'/home/user/data/clean/clean_{i}.csv', index=False)
EOF
python3 /tmp/generate_clean.py

cat << 'EOF' > /tmp/generate_evil.py
import pandas as pd
import numpy as np
import os
np.random.seed(99)
os.makedirs('/home/user/data/evil/', exist_ok=True)
for i in range(10):
    # Base signal
    base = np.random.randn(100)
    # 5 features that are just the base signal with tiny noise
    data = {f'sensor_{j}': base + np.random.normal(0, 0.01, 100) for j in range(5)}
    df = pd.DataFrame(data)
    df.to_csv(f'/home/user/data/evil/evil_{i}.csv', index=False)
EOF
python3 /tmp/generate_evil.py

cat << 'EOF' > /home/user/app/nginx.conf
events {}
http {
    server {
        listen 8080;
        # INTENTIONAL BUG: wrong port
        location /upload {
            proxy_pass http://127.0.0.1:5001; 
        }
    }
}
EOF

cat << 'EOF' > /home/user/app/app.py
from flask import Flask, request
import redis
import subprocess
import os

app = Flask(__name__)
r = redis.Redis(host='localhost', port=6379, db=0)

@app.route('/upload', methods=['POST'])
def upload():
    if 'file' not in request.files:
        return "No file part", 400
    file = request.files['file']
    filepath = f"/tmp/{file.filename}"
    file.save(filepath)

    # AGENT MUST IMPLEMENT DETECTOR CALL HERE
    # result = subprocess.run(['python3', '/home/user/app/detector.py', filepath])
    # if result.returncode == 1:
    #     return "Spoofed", 400

    r.incr('processed_files')
    return "OK", 200

if __name__ == '__main__':
    app.run(port=5000)
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
