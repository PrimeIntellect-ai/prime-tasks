#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server
    pip3 install pytest flask redis gunicorn pandas scipy

    mkdir -p /app /tests/clean /tests/evil

    cat << 'EOF' > /app/start.sh
#!/bin/bash
redis-server --daemonize yes
gunicorn --bind 127.0.0.1:5000 app:app --daemon --chdir /app
nginx -c /app/nginx.conf
EOF
    chmod +x /app/start.sh

    cat << 'EOF' > /app/nginx.conf
events {}
http {
    server {
        listen 8080;
        location / {
            proxy_pass http://127.0.0.1:8000; # AGENT MUST FIX THIS TO 5000
        }
    }
}
EOF

    cat << 'EOF' > /app/app.py
from flask import Flask, request
import redis
app = Flask(__name__)
r = redis.Redis(host='localhost', port=6379, db=0)

@app.route('/upload', methods=['POST'])
def upload():
    r.lpush('data_queue', request.data)
    return "OK", 200
EOF

    cat << 'EOF' > /app/sensor_metadata.csv
sensor_id,status
1,active
2,active
3,inactive
4,active
EOF

    cat << 'EOF' > /tests/clean/clean1.csv
sensor_id,timestamp,value
1,1000,50.1
1,1001,49.9
2,1002,50.5
2,1003,49.5
3,1004,999.9
4,1005,
1,1006,50.0
EOF

    cat << 'EOF' > /tests/evil/evil_missing.csv
sensor_id,timestamp,value
1,1000,50.1
1,1001,
1,1002,
1,1003,50.0
EOF

    cat << 'EOF' > /tests/evil/evil_ttest.csv
sensor_id,timestamp,value
1,1000,55.0
1,1001,55.1
1,1002,54.9
1,1003,55.0
1,1004,55.2
1,1005,54.8
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
