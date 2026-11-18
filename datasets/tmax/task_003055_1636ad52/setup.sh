#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server
    pip3 install pytest redis flask requests

    mkdir -p /app/corpora/evil
    mkdir -p /app/corpora/clean
    mkdir -p /app/services

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
python3 /app/services/emitter.py &
python3 /app/services/store_api.py &
EOF
    chmod +x /app/start_services.sh

    cat << 'EOF' > /app/services/emitter.py
import time
while True:
    time.sleep(10)
EOF

    cat << 'EOF' > /app/services/store_api.py
from flask import Flask, request
import json
app = Flask(__name__)
@app.route('/api/store', methods=['POST'])
def store():
    with open('/tmp/store_api_received.log', 'a') as f:
        f.write(json.dumps(request.json) + '\n')
    return "OK", 200
if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8002)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
