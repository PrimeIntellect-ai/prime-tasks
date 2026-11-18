#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip redis-server nginx
pip3 install pytest flask redis numpy requests

mkdir -p /app/api
mkdir -p /app/nginx
mkdir -p /home/user

cat << 'EOF' > /app/nginx/nginx.conf
events {}
http {
    server {
        listen 8080;

        location / {
            root /var/www/html;
        }
        # The /api/ location is missing and needs to be added by the user
    }
}
EOF

cat << 'EOF' > /app/api/app.py
from flask import Flask, request, jsonify
import subprocess
import tempfile
import json
import redis
import os

app = Flask(__name__)
cache = redis.Redis(host='localhost', port=6379)

@app.route('/process', methods=['POST'])
def process():
    data = request.json
    if not data or 'signal' not in data:
        return jsonify({"error": "No signal provided"}), 400

    with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.json') as f:
        json.dump(data['signal'], f)
        tmp_name = f.name

    try:
        res = subprocess.run(['python3', '/home/user/process_signal.py', tmp_name], capture_output=True, text=True, check=True)
        out = json.loads(res.stdout)
        os.remove(tmp_name)
        return jsonify(out)
    except Exception as e:
        if os.path.exists(tmp_name):
            os.remove(tmp_name)
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

cat << 'EOF' > /home/user/process_signal.py
import sys
import json
import numpy as np

def main():
    if len(sys.argv) != 2:
        sys.exit(1)

    with open(sys.argv[1], 'r') as f:
        signal = json.load(f)

    # TODO: Implement the correct processing logic

    print(json.dumps({"total_energy": 0.0, "weighted_centroid": 0.0, "peak_index": 0}))

if __name__ == '__main__':
    main()
EOF

cat << 'EOF' > /app/oracle_process_signal
#!/usr/bin/env python3
import sys
import json
import math
import numpy as np

def main():
    if len(sys.argv) != 2:
        sys.exit(1)

    with open(sys.argv[1], 'r') as f:
        signal = json.load(f)

    N = len(signal)
    n = np.arange(N)
    w = 0.5 - 0.5 * np.cos(2 * np.pi * n / (N - 1))

    windowed = np.array(signal) * w
    fft_res = np.fft.rfft(windowed)
    P = np.abs(fft_res)**2

    total_energy = math.fsum(P)
    weighted_centroid = math.fsum(k * P[k] for k in range(len(P))) / total_energy
    peak_index = int(np.argmax(P))

    out = {
        "total_energy": total_energy,
        "weighted_centroid": weighted_centroid,
        "peak_index": peak_index
    }
    print(json.dumps(out))

if __name__ == '__main__':
    main()
EOF

chmod +x /app/oracle_process_signal

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
