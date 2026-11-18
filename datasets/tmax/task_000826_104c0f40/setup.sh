#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server jq curl
    pip3 install pytest flask redis pandas

    mkdir -p /home/user/app/db
    mkdir -p /home/user/corpora/clean
    mkdir -p /home/user/corpora/evil

    cat << 'EOF' > /home/user/corpora/clean/clean_1.json
{"age": 30, "clicks": 5, "amount": 100.5}
EOF
    cat << 'EOF' > /home/user/corpora/clean/clean_2.json
{"age": 18, "clicks": 0, "amount": 50}
EOF

    cat << 'EOF' > /home/user/corpora/evil/evil_1.json
{"age": null, "clicks": 5, "amount": 100.5}
EOF
    cat << 'EOF' > /home/user/corpora/evil/evil_2.json
{"age": "30", "clicks": 5, "amount": 100.5}
EOF
    cat << 'EOF' > /home/user/corpora/evil/evil_3.json
{"age": 30.5, "clicks": 5, "amount": 100.5}
EOF
    cat << 'EOF' > /home/user/corpora/evil/evil_4.json
{"age": 30, "clicks": null, "amount": 100.5}
EOF

    cat << 'EOF' > /home/user/app/config.env
REDIS_PORT=6380
VALIDATOR_SCRIPT=
EOF

    cat << 'EOF' > /home/user/app/api.py
import os
import json
import subprocess
from flask import Flask, request
import redis

app = Flask(__name__)

def load_config():
    config = {}
    if os.path.exists('/home/user/app/config.env'):
        with open('/home/user/app/config.env') as f:
            for line in f:
                if '=' in line:
                    k, v = line.strip().split('=', 1)
                    config[k] = v
    return config

@app.route('/ingest', methods=['POST'])
def ingest():
    config = load_config()
    data = request.get_json(force=True)

    val_script = config.get('VALIDATOR_SCRIPT', '')
    if val_script:
        tmp_file = '/tmp/req.json'
        with open(tmp_file, 'w') as f:
            json.dump(data, f)
        res = subprocess.run([val_script, tmp_file])
        if res.returncode != 0:
            return "Invalid", 400

    r = redis.Redis(host='localhost', port=int(config.get('REDIS_PORT', 6379)))
    r.lpush('queue', json.dumps(data))
    return "OK", 200

if __name__ == '__main__':
    app.run(port=5000, host='0.0.0.0')
EOF

    cat << 'EOF' > /home/user/app/worker.py
import os
import json
import redis
import pandas as pd
import sqlite3
import time

def load_config():
    config = {}
    if os.path.exists('/home/user/app/config.env'):
        with open('/home/user/app/config.env') as f:
            for line in f:
                if '=' in line:
                    k, v = line.strip().split('=', 1)
                    config[k] = v
    return config

config = load_config()
r = redis.Redis(host='localhost', port=int(config.get('REDIS_PORT', 6379)))
conn = sqlite3.connect('/home/user/app/db/transactions.db')

while True:
    try:
        item = r.brpop('queue', timeout=1)
        if item:
            data = json.loads(item[1])
            df = pd.DataFrame([data])
            df.to_sql('events', conn, if_exists='append', index=False)
    except Exception as e:
        pass
    time.sleep(0.1)
EOF

    cat << 'EOF' > /home/user/app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
nohup python3 /home/user/app/api.py > /home/user/app/api.log 2>&1 &
nohup python3 /home/user/app/worker.py > /home/user/app/worker.log 2>&1 &
echo "Services started."
EOF
    chmod +x /home/user/app/start_services.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
