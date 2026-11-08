#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server gcc
    pip3 install pytest flask redis waitress gunicorn

    mkdir -p /app

    # Create the Flask webhook receiver
    cat << 'EOF' > /app/webhook.py
from flask import Flask, request
import redis

app = Flask(__name__)
r = redis.Redis(host='localhost', port=6379, db=0)

@app.route('/submit', methods=['POST'])
def submit():
    data = request.data.decode('utf-8')
    r.lpush('config_queue', data)
    return "OK"

if __name__ == '__main__':
    app.run(port=8080)
EOF

    # Create the oracle parser as a compiled C binary
    cat << 'EOF' > /tmp/oracle.c
#include <stdlib.h>
int main() {
    system("python3 -c \"import sys, re; text = sys.stdin.read(); text = re.sub(r'\\s+', '', text); text = text.replace('GigabitEthernet', 'Gi'); pairs = re.findall(r'([a-zA-Z0-9_.-]+)[:=]([a-zA-Z0-9_.-]+)', text); [print(f'{k}={v}') for k, v in sorted(pairs)]\"");
    return 0;
}
EOF
    gcc -o /app/oracle_parser /tmp/oracle.c
    rm /tmp/oracle.c
    chmod +x /app/oracle_parser

    # Create user
    useradd -m -s /bin/bash user || true

    # Ensure home directory permissions
    chmod -R 777 /home/user
