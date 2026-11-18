#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx curl procps
    pip3 install pytest flask numpy pandas

    mkdir -p /app/data/clean
    mkdir -p /app/data/evil
    mkdir -p /app/client_temp /app/proxy_temp /app/fastcgi_temp /app/uwsgi_temp /app/scgi_temp

    cat << 'EOF' > /app/nginx.conf
pid /app/nginx.pid;
error_log /app/error.log;
events {}
http {
    client_body_temp_path /app/client_temp;
    proxy_temp_path       /app/proxy_temp;
    fastcgi_temp_path     /app/fastcgi_temp;
    uwsgi_temp_path       /app/uwsgi_temp;
    scgi_temp_path        /app/scgi_temp;
    access_log /app/access.log;
    server {
        listen 127.0.0.1:8080;
        location / {
            return 200 "Nginx is running";
        }
        # The /ingest location is missing and needs to be fixed by the agent
    }
}
EOF

    cat << 'EOF' > /app/receiver.py
from flask import Flask, request
import subprocess
import tempfile
import os

app = Flask(__name__)

@app.route('/ingest', methods=['POST'])
def ingest():
    data = request.get_data()
    with tempfile.NamedTemporaryFile(delete=False, suffix=".json") as f:
        f.write(data)
        temp_path = f.name

    try:
        if not os.path.exists("/home/user/detector.py"):
            return "Detector missing", 500
        res = subprocess.run(["python3", "/home/user/detector.py", temp_path])
        if res.returncode == 0:
            return "OK", 200
        else:
            return "Not Acceptable", 406
    except Exception as e:
        return str(e), 500
    finally:
        if os.path.exists(temp_path):
            os.remove(temp_path)

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    cat << 'EOF' > /app/data/clean/clean1.json
[
  {"timestamp": 1690000000, "latency": 46.0, "cpu_load": 0.4},
  {"timestamp": 1690000005, "latency": 46.0, "cpu_load": 0.4},
  {"timestamp": 1690000010, "latency": 46.0, "cpu_load": 0.4}
]
EOF

    cat << 'EOF' > /app/data/clean/clean2.json
[
  {"timestamp": 1690000000, "latency": 55.0, "cpu_load": 0.4},
  {"timestamp": 1690000005, "latency": 55.0, "cpu_load": 0.4},
  {"timestamp": 1690000010, "latency": 55.0, "cpu_load": 0.4}
]
EOF

    cat << 'EOF' > /app/data/evil/evil1.json
[
  {"timestamp": 1690000000, "latency": 75.0, "cpu_load": 0.4},
  {"timestamp": 1690000005, "latency": 75.0, "cpu_load": 0.4},
  {"timestamp": 1690000010, "latency": 75.0, "cpu_load": 0.4}
]
EOF

    cat << 'EOF' > /app/data/evil/evil2.json
[
  {"timestamp": 1690000000, "latency": 90.0, "cpu_load": 0.4},
  {"timestamp": 1690000005, "latency": 90.0, "cpu_load": 0.4},
  {"timestamp": 1690000010, "latency": 90.0, "cpu_load": 0.4}
]
EOF

    useradd -m -s /bin/bash user || true

    # Ensure services start when bash is invoked
    cat << 'EOF' >> /etc/bash.bashrc
pgrep -f "nginx: master process" > /dev/null || nginx -c /app/nginx.conf
pgrep -f "receiver.py" > /dev/null || nohup python3 /app/receiver.py > /dev/null 2>&1 &
EOF

    chmod -R 777 /app
    chmod -R 777 /home/user
