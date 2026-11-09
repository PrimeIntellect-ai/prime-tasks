#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server build-essential curl
    pip3 install pytest flask redis

    mkdir -p /app/api /app/corpora/clean /app/corpora/evil

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
python3 /app/api/app.py &
EOF
    chmod +x /app/start_services.sh

    cat << 'EOF' > /app/api/app.py
from flask import Flask, request
import os

app = Flask(__name__)

@app.route('/health', methods=['GET'])
def health():
    return "OK", 200

@app.route('/webhook', methods=['POST'])
def webhook():
    data = request.json
    return "Received", 200

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    cat << 'EOF' > /app/corpora/clean/clean1.csv
1,1620000000,"val1","val2","long
value","long
value2"
EOF

    cat << 'EOF' > /app/corpora/evil/evil1.csv
2,1620000000,"$(rm -rf /)","safe","safe2","safe3"
3,1620000000,"short","<very long string 100 chars>","a","b"
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
