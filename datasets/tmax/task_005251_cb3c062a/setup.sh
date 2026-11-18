#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server curl
    pip3 install pytest flask redis

    mkdir -p /app/data

    cat << 'EOF' > /app/c2_server.py
from flask import Flask, request
import redis
import uuid

app = Flask(__name__)
r = redis.Redis(host='localhost', port=6379, db=0)

@app.route('/', methods=['POST'])
def handle_payload():
    data = request.get_data(as_text=True)
    if "EICAR-STANDARD-ANTIVIRUS-TEST-FILE" in data:
        raise Exception("Poison pill detected")
    r.set(f"payload:{uuid.uuid4()}", data)
    return "OK", 200

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    cat << 'EOF' > /app/aggregator.sh
#!/bin/bash

while IFS= read -r line; do
    curl -s -f -X POST -d "$line" http://127.0.0.1:5000/ > /dev/null
done < "/app/data/raw_payloads.txt"
EOF
    chmod +x /app/aggregator.sh

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
nohup python3 /app/c2_server.py > /app/c2.log 2>&1 &
echo "Services started"
EOF
    chmod +x /app/start_services.sh

    python3 -c "
import base64
import os

with open('/app/data/raw_payloads.txt', 'w') as f:
    for i in range(1, 10001):
        if i == 7342:
            f.write('EICAR-STANDARD-ANTIVIRUS-TEST-FILE-12345\n')
        else:
            f.write(base64.b64encode(os.urandom(16)).decode('utf-8') + '\n')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
