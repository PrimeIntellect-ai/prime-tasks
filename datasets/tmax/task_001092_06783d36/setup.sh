#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server curl
    pip3 install pytest pandas numpy flask redis gunicorn

    mkdir -p /home/user/app
    mkdir -p /home/user/eval_corpus/evil
    mkdir -p /home/user/eval_corpus/clean

    cat << 'EOF' > /home/user/eval_corpus/clean/data1.csv
A,B,C
1,2,3
4,5,6
7,8,9
EOF

    cat << 'EOF' > /home/user/eval_corpus/evil/data1.csv
A,B,C
1.0,2.0,3.0
4.0,,6.0
7.0,8.0,9.0
EOF

    cat << 'EOF' > /home/user/app/api.py
from flask import Flask, request
import redis

app = Flask(__name__)
r = redis.Redis(host='localhost', port=6379, db=0)

@app.route('/upload', methods=['POST'])
def upload():
    file = request.files.get('file')
    # Missing validation
    r.lpush('dataset_queue', file.read())
    return "OK", 200
EOF

    cat << 'EOF' > /home/user/app/start_services.sh
#!/bin/bash
redis-server --daemonize yes --port 6380 # Incorrect port
gunicorn -w 1 -b 127.0.0.1:5001 api:app & # Incorrect port
nginx -c /home/user/app/nginx.conf
EOF
    chmod +x /home/user/app/start_services.sh

    cat << 'EOF' > /home/user/app/nginx.conf
events {}
http {
    server {
        listen 8080;
        location / {
            proxy_pass http://127.0.0.1:5001; # Pointing to wrong Flask port
        }
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
