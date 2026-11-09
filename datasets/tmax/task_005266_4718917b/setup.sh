#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server g++ redis-tools
    pip3 install pytest flask redis requests numpy pandas scipy

    mkdir -p /app/api /app/worker /app/corpora/clean /app/corpora/evil /app/tests

    cat << 'EOF' > /app/api/app.py
import os
from flask import Flask, request, jsonify
import redis

app = Flask(__name__)
redis_client = redis.Redis(host=os.environ.get('REDIS_HOST', 'invalid_host'), port=6379, decode_responses=True)

@app.route('/validate', methods=['POST'])
def validate():
    filepath = request.json.get('filepath')
    if not filepath:
        return jsonify({"error": "filepath required"}), 400

    # Push job to queue
    redis_client.rpush('job_queue', f"job:{filepath}")

    # Wait for result from worker
    res = redis_client.blpop(f"result_{filepath}", timeout=10)
    if res:
        # res is a tuple (list_name, value)
        # remove potential quotes if redis-cli added them
        val = res[1].strip().strip('"')
        return jsonify({"status": val})
    else:
        return jsonify({"error": "timeout"}), 504

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

    cat << 'EOF' > /app/worker/worker.sh
#!/bin/bash
while true; do
    job=$(redis-cli --raw blpop job_queue 0 | tail -n 1)
    filepath=$(echo "$job" | cut -d':' -f2-)
    result=$(/app/worker/detector "$filepath")
    redis-cli --raw lpush "result_$filepath" "$result"
done
EOF
    chmod +x /app/worker/worker.sh

    cat << 'EOF' > /app/tests/run_tests.py
import requests
import glob
import sys

def run_tests():
    clean_files = glob.glob('/app/corpora/clean/*.csv')
    evil_files = glob.glob('/app/corpora/evil/*.csv')

    success = True

    for c in clean_files:
        try:
            r = requests.post('http://localhost:5000/validate', json={'filepath': c})
            status = r.json().get('status')
            if status != 'VALID':
                print(f"FAIL: {c} returned {status}, expected VALID")
                success = False
        except Exception as e:
            print(f"Error testing {c}: {e}")
            success = False

    for e in evil_files:
        try:
            r = requests.post('http://localhost:5000/validate', json={'filepath': e})
            status = r.json().get('status')
            if status != 'ANOMALOUS':
                print(f"FAIL: {e} returned {status}, expected ANOMALOUS")
                success = False
        except Exception as ex:
            print(f"Error testing {e}: {ex}")
            success = False

    if success:
        print("All tests passed.")
        sys.exit(0)
    else:
        print("Some tests failed.")
        sys.exit(1)

if __name__ == '__main__':
    run_tests()
EOF

    cat << 'EOF' > /tmp/gen_data.py
import numpy as np
import pandas as pd
import os

np.random.seed(42)

def make_clean(path):
    sig = np.random.normal(50.0, 2.0, 100)
    bg = np.random.normal(10.0, 5.0, 100)
    noise = np.random.normal(0, 1.0, 100)
    df = pd.DataFrame({'id': range(100), 'signal': sig, 'background': bg, 'noise': noise})
    df.to_csv(path, index=False)

def make_evil_mean(path):
    sig = np.random.normal(56.0, 2.0, 100)
    bg = np.random.normal(10.0, 5.0, 100)
    noise = np.random.normal(0, 1.0, 100)
    df = pd.DataFrame({'id': range(100), 'signal': sig, 'background': bg, 'noise': noise})
    df.to_csv(path, index=False)

def make_evil_dupe(path):
    sig = np.random.normal(50.0, 2.0, 100)
    bg = np.random.normal(10.0, 5.0, 100)
    noise = np.random.normal(0, 1.0, 100)
    df = pd.DataFrame({'id': range(100), 'signal': sig, 'background': bg, 'noise': noise})
    df.iloc[50] = df.iloc[10]
    df.to_csv(path, index=False)

for i in range(20):
    make_clean(f"/app/corpora/clean/clean_{i}.csv")

for i in range(10):
    make_evil_mean(f"/app/corpora/evil/evil_mean_{i}.csv")

for i in range(10):
    make_evil_dupe(f"/app/corpora/evil/evil_dupe_{i}.csv")
EOF

    python3 /tmp/gen_data.py
    rm /tmp/gen_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
