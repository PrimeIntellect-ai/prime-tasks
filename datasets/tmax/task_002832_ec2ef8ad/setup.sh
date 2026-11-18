#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip redis-server curl
pip3 install --default-timeout=100 pytest flask redis numpy scipy

mkdir -p /app

cat << 'EOF' > /app/start.sh
#!/bin/bash
redis-server --daemonize yes
python3 /app/server.py &
sleep 2
EOF
chmod +x /app/start.sh

cat << 'EOF' > /app/server.py
from flask import Flask, jsonify, request
import json

app = Flask(__name__)

@app.route('/job', methods=['GET'])
def get_job():
    return jsonify({"alpha": 0.05, "duration": 10.0, "dt": 0.01})

@app.route('/submit', methods=['POST'])
def submit():
    data = request.json
    with open('/home/user/result_spectrum.json', 'w') as f:
        json.dump(data, f)
    return jsonify({"status": "success"})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

cat << 'EOF' > /app/worker.py
import requests
import numpy as np

# Broken worker
# TODO: Fetch from http://127.0.0.1:5000/job
alpha = 0.05
duration = 10.0
dt = 0.01

# Bad solver
Nx = 5
x = np.linspace(0, 1, Nx)
u = np.zeros(Nx)

# TODO: Fix the PDE solver, do FFT, and POST to /submit
print("Not implemented")
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
