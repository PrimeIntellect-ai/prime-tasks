#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip curl redis-server
pip3 install pytest fastapi uvicorn redis requests

curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt-get install -y nodejs

mkdir -p /app/api /app/processor /app/logs
touch /app/logs/processed.log

cat << 'EOF' > /app/api/main.py
from fastapi import FastAPI, Request
import redis
import json

app = FastAPI()
r = redis.Redis(host='127.0.0.1', port=6379, db=0)

@app.post("/submit_log")
async def submit_log(request: Request):
    payload = await request.json()
    r.lpush('log_queue', json.dumps(payload))
    return {"status": "queued"}
EOF

cat << 'EOF' > /app/processor/logger.js
const redis = require('redis');
const fs = require('fs');

const client = redis.createClient({ url: 'redis://127.0.0.1:6379' });

function extractCausation(errorObj) {
    let causes = [];
    let current = errorObj;
    while (current != null) {
        if (current.message) causes.push(current.message);
        if (current.innerError) {
            current = current.innerError;
        } else if (current.cause) {
            current = current.cause;
        }
    }
    return causes.join(' -> ');
}

async function processQueue() {
    await client.connect();
    while (true) {
        try {
            const result = await client.brPop('log_queue', 0);
            if (result) {
                const payload = JSON.parse(result.element);
                const event = payload.event || 'unknown';
                let chain = '';
                if (payload.error) {
                    chain = extractCausation(payload.error);
                }
                const logLine = `Event: ${event} | Chain: ${chain}\n`;
                fs.appendFileSync('/app/logs/processed.log', logLine);
            }
        } catch (err) {
            console.error(err);
        }
    }
}

processQueue();
EOF

cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
cd /app/api && uvicorn main:app --host 127.0.0.1 --port 8000 &
cd /app/processor && node logger.js &
wait
EOF
chmod +x /app/start_services.sh

cd /app/processor && npm init -y && npm install redis

useradd -m -s /bin/bash user || true
chmod -R 777 /app
chmod -R 777 /home/user
