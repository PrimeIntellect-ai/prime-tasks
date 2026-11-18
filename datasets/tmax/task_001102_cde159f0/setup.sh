#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nodejs npm redis-server curl
    pip3 install pytest scipy redis matplotlib

    mkdir -p /app

    cat << 'EOF' > /app/api.js
const express = require('express');
const redis = require('redis');
const app = express();
app.use(express.json());

const client = redis.createClient();
client.connect();

app.post('/simulate', async (req, res) => {
    // Add auth check here

    const sequences = req.body.sequences;
    await client.del('jobs');
    await client.del('results');

    for (let seq of sequences) {
        await client.lPush('jobs', seq);
    }

    let results = [];
    // Fix the non-reproducible aggregation here
    // Implement regression here
    // Call plot.py here

    res.json({
        total_peak: 0,
        regression_slope: 0,
        regression_intercept: 0
    });
});

app.listen(8080, () => console.log('API listening on 8080'));
EOF

    cat << 'EOF' > /app/worker.py
import redis
import json
import time

r = redis.Redis(host='localhost', port=6379, decode_responses=True)

def process():
    while True:
        job = r.rpop('jobs')
        if job:
            seq = job
            # Implement ODE solver here

            result = {
                "sequence": seq,
                "length": len(seq),
                "peak_B": 0 # Replace with actual peak
            }
            r.lpush('results', json.dumps(result))
        else:
            time.sleep(1)

if __name__ == '__main__':
    process()
EOF

    cat << 'EOF' > /app/package.json
{
  "name": "bio-sim",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2",
    "redis": "^4.6.7"
  }
}
EOF

    touch /app/plot.py

    cd /app && npm install

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
