#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server
    pip3 install pytest flask redis numpy scipy scikit-learn requests

    mkdir -p /app

    cat << 'EOF' > /app/data_service.py
import json
import numpy as np
import redis
from flask import Flask, jsonify

app = Flask(__name__)
r = redis.Redis(host='localhost', port=6379, db=0)

@app.route('/data', methods=['GET'])
def get_data():
    data = r.get('spectra')
    if data:
        return jsonify({"spectra": json.loads(data)})
    return jsonify({"error": "not found"}), 404

def generate_data():
    np.random.seed(42)
    n_samples = 1000
    n_features = 200
    x = np.arange(n_features)

    peaks = [40, 90, 160]
    widths = [5, 8, 10]

    components = np.zeros((3, n_features))
    for i in range(3):
        components[i] = np.exp(-((x - peaks[i])**2) / (2 * widths[i]**2))

    weights = np.random.uniform(0.1, 1.0, size=(n_samples, 3))
    clean_data = np.dot(weights, components)

    # baseline drift
    baseline = np.zeros((n_samples, n_features))
    for i in range(n_samples):
        c0 = np.random.uniform(0, 10)
        c1 = np.random.uniform(-0.1, 0.1)
        c2 = np.random.uniform(0, 0.001)
        baseline[i] = c0 + c1 * x + c2 * x**2

    noise = np.random.normal(0, 0.05, size=(n_samples, n_features))

    final_data = clean_data + baseline + noise
    r.set('spectra', json.dumps(final_data.tolist()))

if __name__ == '__main__':
    generate_data()
    app.run(host='0.0.0.0', port=5000)
EOF

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
sleep 2
python3 /app/data_service.py &
sleep 2
EOF
    chmod +x /app/start_services.sh

    cat << 'EOF' > /app/verify.py
import json
import sys

try:
    with open('/home/user/result.json', 'r') as f:
        data = json.load(f)

    peaks = data.get('peaks', [])
    if len(peaks) != 3:
        print("Error: Expected 3 peaks in result.json")
        sys.exit(1)

    extracted_means = [p['mean_index'] for p in peaks]
    true_means = [40, 90, 160]

    mae = sum(abs(e - t) for e, t in zip(extracted_means, true_means)) / 3.0
    print(f"MAE: {mae}")

    if mae <= 3.0:
        print("Success: Metric threshold met.")
        sys.exit(0)
    else:
        print(f"Failure: MAE {mae} exceeds threshold 3.0")
        sys.exit(1)
except Exception as e:
    print(f"Verification failed with exception: {e}")
    sys.exit(1)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
