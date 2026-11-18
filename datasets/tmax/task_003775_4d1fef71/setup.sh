#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server build-essential curl
    pip3 install pytest flask redis requests

    mkdir -p /app
    mkdir -p /home/user/logs
    mkdir -p /home/user/history

    cat << 'EOF' > /app/config_api.py
from flask import Flask, request
import redis
import os
import time

app = Flask(__name__)
r = redis.Redis(host='localhost', port=6379, db=0)

LOG_FILE = '/home/user/logs/config_updates.log'
HISTORY_DIR = '/home/user/history'

@app.route('/update', methods=['POST'])
def update():
    data = request.json
    version = data['version']
    content = data['content']
    state = data['state']

    filename = os.path.join(HISTORY_DIR, f"app_v{version}.conf")
    with open(filename, 'w') as f:
        f.write(content)

    with open(LOG_FILE, 'a') as f:
        f.write("[BEGIN_UPDATE]\n")
        f.write(f"TIMESTAMP: {int(time.time())}\n")
        f.write(f"TARGET_FILE: {filename}\n")
        f.write(f"STATE: {state}\n")
        f.write("[END_UPDATE]\n")

    return "OK", 200

if __name__ == '__main__':
    os.makedirs(HISTORY_DIR, exist_ok=True)
    os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
    app.run(host='0.0.0.0', port=8080)
EOF

    cat << 'EOF' > /app/load_generator.py
import requests
import random
import string
import time

# Create base config of ~4.5KB
base_config = [f"config_param_{i} = " + "".join(random.choices(string.ascii_letters + string.digits, k=50)) for i in range(75)]

for v in range(1, 1001):
    config = list(base_config)
    # Change 1-2 lines
    for _ in range(random.randint(1, 2)):
        idx = random.randint(0, len(config)-1)
        config[idx] = f"config_param_{idx} = " + "".join(random.choices(string.ascii_letters + string.digits, k=50))
    base_config = config

    state = "COMMITTED" if random.random() > 0.05 else "FAILED"

    try:
        requests.post('http://localhost:8080/update', json={
            'version': v,
            'content': "\n".join(config) + "\n",
            'state': state
        })
    except Exception as e:
        print(f"Failed to send update {v}: {e}")
EOF

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
python3 /app/config_api.py &
API_PID=$!

# Wait for API to be ready
while ! curl -s http://localhost:8080/ > /dev/null; do
    sleep 0.5
done

python3 /app/load_generator.py
echo "Load generation complete."
EOF
    chmod +x /app/start_services.sh

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
