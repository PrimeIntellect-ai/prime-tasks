#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server nginx supervisor socat netcat gawk curl
    pip3 install pytest flask numpy redis

    mkdir -p /app

    # Create Sensor Simulator
    cat << 'EOF' > /app/sensor_sim.py
import socket
import numpy as np
import time

np.random.seed(42)

server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(('127.0.0.1', 9001))
server.listen(5)

while True:
    conn, addr = server.accept()
    try:
        for _ in range(100):
            raw_signal = np.random.normal(50, 10, 100)
            line = ",".join([f"{x:.2f}" for x in raw_signal]) + "\n"
            conn.sendall(line.encode('utf-8'))
            time.sleep(0.005)
    except:
        pass
    conn.close()
EOF

    # Create Feature API
    cat << 'EOF' > /app/api.py
from flask import Flask
import redis
import json

app = Flask(__name__)
r = redis.Redis(host='127.0.0.1', port=6379, db=0)

@app.route('/features')
def features():
    data = r.get('latest_stats')
    if data:
        return data.decode('utf-8'), 200, {'Content-Type': 'application/json'}
    return '{"error": "no data"}', 404, {'Content-Type': 'application/json'}

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    # Configure Nginx with broken configuration (listening on 8080 but no proxy)
    cat << 'EOF' > /etc/nginx/sites-available/default
server {
    listen 8080;
    server_name localhost;

    location / {
        return 200 "Nginx is running but not configured correctly.\n";
    }
}
EOF

    # Supervisor configuration
    mkdir -p /var/log/supervisor
    cat << 'EOF' > /etc/supervisor/conf.d/supervisord.conf
[supervisord]
nodaemon=true
user=root
logfile=/var/log/supervisor/supervisord.log
pidfile=/var/run/supervisord.pid

[program:redis]
command=/usr/bin/redis-server
autostart=true
autorestart=true

[program:nginx]
command=/usr/sbin/nginx -g "daemon off;"
autostart=true
autorestart=true

[program:sensor_sim]
command=python3 /app/sensor_sim.py
autostart=true
autorestart=true

[program:api]
command=python3 /app/api.py
autostart=true
autorestart=true
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
