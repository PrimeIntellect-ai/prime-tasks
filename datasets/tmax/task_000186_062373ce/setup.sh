#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y curl gnupg python3 python3-pip redis-server

    # Install Node.js 18
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt-get install -y nodejs

    pip3 install pytest flask redis requests

    mkdir -p /home/user/app/diagnostics
    mkdir -p /home/user/app/logs

    # Install redis npm package
    cd /home/user/app
    npm init -y
    npm install redis

    cat << 'EOF' > /home/user/app/api.py
import time
import uuid
import json
from flask import Flask, request, jsonify
import redis

app = Flask(__name__)
r = redis.Redis(host='127.0.0.1', port=6379, db=0)

@app.route('/process', methods=['POST'])
def process():
    data = request.json
    job_id = str(uuid.uuid4())
    job_data = {
        'id': job_id,
        'payload': data
    }
    r.lpush('job_queue', json.dumps(job_data))

    # Wait for result
    for _ in range(50):
        res = r.get(f'result_{job_id}')
        if res:
            return jsonify({'status': 'success', 'result': json.loads(res)})
        time.sleep(0.1)
    return jsonify({'status': 'timeout'}), 504

if __name__ == '__main__':
    app.run(port=5000)
EOF

    cat << 'EOF' > /home/user/app/worker.js
const redis = require('redis');
const client = redis.createClient({ url: 'redis://127.0.0.1:6379' });

client.connect().catch(console.error);

function calculateSum(node) {
    if (!node) return 0;
    let sum = node.value || 0;
    for (let child of (node.children || [])) {
        sum += calculateSum(child);
    }
    return sum;
}

async function processJobs() {
    while (true) {
        try {
            const result = await client.brPop('job_queue', 0);
            if (result) {
                const job = JSON.parse(result.element);
                const sum = calculateSum(job.payload);
                await client.set(`result_${job.id}`, JSON.stringify(sum));
            }
        } catch (e) {
            console.error(e);
        }
    }
}

processJobs();
EOF

    echo "Binary data ... CRITICAL_JOB_ID_99482 ... more data" > /home/user/app/diagnostics/worker_heap.dump

    cat << 'EOF' > /home/user/verify.py
import time
import requests
import sys

jobs = []
for i in range(100):
    nodeA = {'id': f'A_{i}', 'value': 1, 'children': []}
    nodeB = {'id': f'B_{i}', 'value': 2, 'children': [nodeA]}
    nodeA['children'].append(nodeB) # cyclic
    jobs.append(nodeA)

start = time.time()
for job in jobs:
    try:
        r = requests.post('http://127.0.0.1:5000/process', json=job)
        assert r.status_code == 200
    except Exception as e:
        print(f"Failed: {e}")
        sys.exit(1)
duration = time.time() - start
print(duration)
EOF

    cat << 'EOF' > /home/user/app/benchmark.sh
#!/bin/bash
python3 /home/user/verify.py
EOF
    chmod +x /home/user/app/benchmark.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
