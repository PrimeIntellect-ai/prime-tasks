#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        python3-numpy \
        nginx \
        redis-server

    pip3 install pytest flask

    mkdir -p /app

    cat << 'EOF' > /app/start_env.sh
#!/bin/bash
python3 /app/simulator.py &
redis-server --daemonize yes
EOF
    chmod +x /app/start_env.sh

    cat << 'EOF' > /app/simulator.py
import socket
import json
import numpy as np

# Generate a 1-second signal at 1024 Hz with a dominant frequency of 42 Hz 
# and a secondary frequency at 15 Hz, plus noise.
t = np.linspace(0, 1, 1024, endpoint=False)
signal = np.sin(2 * np.pi * 42 * t) + 0.3 * np.sin(2 * np.pi * 15 * t) + np.random.normal(0, 0.1, 1024)
data = json.dumps(signal.tolist())

s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.bind(('127.0.0.1', 9000))
s.listen(5)
while True:
    conn, addr = s.accept()
    conn.sendall(data.encode('utf-8'))
    conn.close()
EOF

    cat << 'EOF' > /app/molecule.json
{
  "nodes": [
    {"id": 0, "base_freq": 10.0},
    {"id": 1, "base_freq": 41.5},
    {"id": 2, "base_freq": 43.1},
    {"id": 3, "base_freq": 42.0},
    {"id": 4, "base_freq": 46.0},
    {"id": 5, "base_freq": 100.0},
    {"id": 6, "base_freq": 41.9}
  ],
  "edges": [
    [0, 1],
    [1, 2],
    [2, 3],
    [3, 6],
    [4, 5],
    [1, 4]
  ]
}
EOF

    cat << 'EOF' > /app/nginx.conf
worker_processes 1;
daemon off;
events { worker_connections 1024; }
http {
    server {
        listen 8080;
        # location /api/ {
        #     proxy_pass http://127.0.0.1:9999/;
        # }
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
