#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server
    pip3 install pytest flask redis requests numpy

    mkdir -p /app

    cat << 'EOF' > /app/api.py
import os
import redis
from flask import Flask, jsonify

app = Flask(__name__)
redis_port = int(os.environ.get('REDIS_PORT', 6380))
cache = redis.Redis(host='localhost', port=redis_port)

@app.route('/api/params')
def params():
    # Will throw an error if Redis is not connected properly
    cache.ping()
    return jsonify({"alpha": 0.25, "N": 50})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

    cat << 'EOF' > /app/oracle_process_source.py
import sys
import requests
import numpy as np

def main():
    if len(sys.argv) < 2:
        return
    seq = sys.argv[1]

    resp = requests.get('http://localhost:5000/api/params')
    data = resp.json()
    alpha = data['alpha']
    N = data['N']

    arr = np.array([1.0 if c in 'CG' else 0.0 for c in seq])
    L = len(arr)

    if L < 3:
        mean_val = np.mean(arr)
        indices = [str(i) for i, val in enumerate(arr) if val > mean_val]
        print(",".join(indices))
        return

    for _ in range(N):
        new_arr = np.copy(arr)
        for i in range(1, L - 1):
            new_arr[i] = arr[i] + alpha * (arr[i+1] - 2*arr[i] + arr[i-1])
        new_arr[0] = 0.0
        new_arr[L-1] = 0.0
        arr = new_arr

    mean_val = np.mean(arr)
    indices = [str(i) for i, val in enumerate(arr) if val > mean_val]
    print(",".join(indices))

if __name__ == "__main__":
    main()
EOF

    cat << 'EOF' > /app/oracle_process
#!/bin/bash
python3 /app/oracle_process_source.py "$@"
EOF
    chmod +x /app/oracle_process

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
