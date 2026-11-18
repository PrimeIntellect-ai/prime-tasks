#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server
    pip3 install pytest flask redis

    mkdir -p /home/user/app
    mkdir -p /home/user/corpora/evil
    mkdir -p /home/user/corpora/clean

    cat << 'EOF' > /home/user/app/api.py
import os
import json
from flask import Flask, request
import redis
from datetime import datetime

app = Flask(__name__)
redis_client = redis.Redis(host='localhost', port=6379, db=0)

@app.route('/ingest', methods=['POST'])
def ingest():
    data = request.json
    dt = datetime.strptime(data['timestamp'], "%Y-%m-%dT%H:%M:%SZ")
    data['parsed_timestamp'] = dt.isoformat()
    redis_client.lpush('telemetry', json.dumps(data))
    return "OK", 200

if __name__ == '__main__':
    app.run(port=5000)
EOF

    cat << 'EOF' > /home/user/app/worker.py
import os
import json
import redis
import time
from datetime import datetime, timezone

redis_client = redis.Redis(host='localhost', port=6379, db=0)

def process():
    while True:
        item = redis_client.brpop('telemetry', timeout=1)
        if item:
            _, data_bytes = item
            data = json.loads(data_bytes)
            now = datetime.now(timezone.utc)
            event_time = datetime.fromisoformat(data['parsed_timestamp'])
            try:
                event_time_aware = event_time.astimezone()
                duration = (now - event_time_aware).total_seconds()
                with open('/home/user/app/processed_events.log', 'a') as f:
                    f.write(json.dumps({"id": data.get("id"), "duration": duration}) + "\n")
            except Exception as e:
                pass

if __name__ == '__main__':
    process()
EOF

    cat << 'EOF' > /home/user/app/start_services.sh
#!/bin/bash
redis-server &
python3 /home/user/app/api.py &
python3 /home/user/app/worker.py &
wait
EOF
    chmod +x /home/user/app/start_services.sh

    cat << 'EOF' > /home/user/app/redis.conf
port 6380
EOF

    cat << 'EOF' > /tmp/gen_corpora.py
import os
import json

os.makedirs('/home/user/corpora/evil', exist_ok=True)
os.makedirs('/home/user/corpora/clean', exist_ok=True)

for i in range(10):
    with open(f'/home/user/corpora/evil/log_{i}.jsonl', 'w') as f:
        for j in range(5):
            f.write(json.dumps({"id": j, "duration": -3600.0 + j}) + "\n")

for i in range(10):
    with open(f'/home/user/corpora/clean/log_{i}.jsonl', 'w') as f:
        for j in range(5):
            f.write(json.dumps({"id": j, "duration": 1.5 + j}) + "\n")
EOF
    python3 /tmp/gen_corpora.py
    rm /tmp/gen_corpora.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
