#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server golang netcat-openbsd curl
    pip3 install pytest flask redis

    mkdir -p /app/corpus/clean /app/corpus/evil

    cat << 'EOF' > /app/producer.py
from flask import Flask, Response
import time

app = Flask(__name__)

@app.route('/data')
def data():
    def generate():
        while True:
            yield "1,100,user1,10.5,food\n"
            time.sleep(1)
    return Response(generate(), mimetype='text/csv')

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

    cat << 'EOF' > /app/consumer.py
import socket
import redis

r = redis.Redis(host='localhost', port=6379, db=0)
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('0.0.0.0', 5001))
s.listen(5)

while True:
    try:
        conn, addr = s.accept()
        with conn:
            while True:
                data = conn.recv(1024)
                if not data:
                    break
    except Exception:
        pass
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
