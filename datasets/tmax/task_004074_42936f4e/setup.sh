#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server curl bc jq
    pip3 install --no-cache-dir pytest flask redis scipy numpy

    mkdir -p /app

    cat << 'EOF' > /app/sequencer.py
from flask import Flask, jsonify
import numpy as np

app = Flask(__name__)

@app.route('/signal', methods=['GET'])
def get_signal():
    np.random.seed(42)
    true_signal = np.random.normal(loc=0.0, scale=1.0, size=1000)
    target_scale = 1.45
    target_shift = -2.10
    raw = (true_signal - target_shift) / target_scale
    return jsonify({"signal": raw.tolist()})

if __name__ == '__main__':
    app.run(port=5000)
EOF

    cat << 'EOF' > /app/scorer.py
from flask import Flask, request, jsonify
import numpy as np
from scipy.stats import gaussian_kde
import redis

app = Flask(__name__)
r = redis.Redis(host='localhost', port=6379, db=0)

@app.route('/score', methods=['POST'])
def score():
    data = request.json
    raw = np.array(data['signal'])
    scale = float(data['scale'])
    shift = float(data['shift'])

    calibrated = raw * scale + shift

    kde = gaussian_kde(calibrated)
    x = np.linspace(-5, 5, 100)
    expected = np.exp(-0.5 * x**2) / np.sqrt(2 * np.pi)

    mse = float(np.mean((kde(x) - expected)**2))
    return jsonify({"mse": mse})

if __name__ == '__main__':
    app.run(port=5001)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
