#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip redis-server nodejs npm curl
pip3 install pytest flask redis

mkdir -p /home/user/app/config
mkdir -p /home/user/app/api
mkdir -p /home/user/app/worker
mkdir -p /home/user/app/archive
mkdir -p /home/user/corpora/clean
mkdir -p /home/user/corpora/evil

cat << 'EOF' > /home/user/app/config/broker.env
REDIS_HOST=127.0.0.1
REDIS_PORT=6379
EOF

cat << 'EOF' > /home/user/app/api/gateway.py
from flask import Flask, request
import redis
import json
import base64

app = Flask(__name__)
# Broken: hardcoded to wrong host
r = redis.Redis(host='localhost', port=9999)

@app.route('/submit', methods=['POST'])
def submit():
    payload = request.data.decode('utf-8')
    r.lpush('log_queue', payload)
    return "OK", 200

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8080)
EOF

cat << 'EOF' > /home/user/app/worker/enforcer.js
const redis = require('redis');
const fs = require('fs');

const client = redis.createClient({
    url: 'redis://127.0.0.1:6379'
});

client.on('error', (err) => console.log('Redis Client Error', err));

async function run() {
    await client.connect();
    while (true) {
        // Broken: not pulling from log_queue correctly
        const item = await client.brPop('wrong_queue', 0);
        if (item) {
            console.log(item);
        }
    }
}

run();
EOF

cat << 'EOF' > /home/user/app/start.sh
#!/bin/bash
redis-server --daemonize yes
source /home/user/app/config/broker.env
python3 /home/user/app/api/gateway.py &
node /home/user/app/worker/enforcer.js &
wait
EOF
chmod +x /home/user/app/start.sh

cd /home/user/app/worker
npm install redis

python3 -c "
import os
import json
import hashlib

clean_dir = '/home/user/corpora/clean/'
evil_dir = '/home/user/corpora/evil/'

for i in range(50):
    log_data = f'Clean log entry {i}'
    log_hash = hashlib.sha256(log_data.encode()).hexdigest()
    payload = {'id': i, 'log': log_data, 'checksum': log_hash}
    with open(os.path.join(clean_dir, f'{i}.json'), 'w') as f:
        json.dump(payload, f)

for i in range(50):
    if i % 3 == 0:
        log_data = f'Evil log entry {i} <script>alert(1)</script>'
    elif i % 3 == 1:
        log_data = f'Evil log entry {i} DROP TABLE users;'
    else:
        log_data = f'Evil log entry {i}'

    if i % 3 == 2:
        log_hash = 'badhash'
    else:
        log_hash = hashlib.sha256(log_data.encode()).hexdigest()

    payload = {'id': i, 'log': log_data, 'checksum': log_hash}
    with open(os.path.join(evil_dir, f'{i}.json'), 'w') as f:
        json.dump(payload, f)
"

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
