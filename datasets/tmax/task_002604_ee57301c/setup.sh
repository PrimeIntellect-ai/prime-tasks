#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server curl
    pip3 install pytest flask redis requests python-dotenv

    mkdir -p /home/user/app
    mkdir -p /home/user/corpora/clean
    mkdir -p /home/user/corpora/evil

    cat << 'EOF' > /home/user/app/nginx.conf
events {}
http {
    server {
        listen 8080;
        location /upload {
            proxy_pass http://127.0.0.1:9999;
        }
    }
}
EOF

    cat << 'EOF' > /home/user/app/settings.env
REDIS_PORT=
FILTER_SCRIPT=
EOF

    cat << 'EOF' > /home/user/app/app.py
import os
import subprocess
from flask import Flask, request
import redis
from dotenv import load_dotenv

load_dotenv('/home/user/app/settings.env')

app = Flask(__name__)
redis_port = os.getenv('REDIS_PORT', '6379')
filter_script = os.getenv('FILTER_SCRIPT', '')

try:
    r = redis.Redis(host='localhost', port=int(redis_port) if redis_port else 6379, db=0)
except:
    r = None

@app.route('/upload', methods=['POST'])
def upload():
    data = request.get_data(as_text=True)
    if not filter_script or not os.path.exists(filter_script):
        return "Filter script not found", 500

    process = subprocess.Popen([filter_script], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    stdout, stderr = process.communicate(input=data)

    if r:
        for line in stdout.strip().split('\n'):
            if line:
                r.rpush('transactions', line)
    return "OK", 200

if __name__ == '__main__':
    app.run(port=5000)
EOF

    cat << 'EOF' > /home/user/app/start_services.sh
#!/bin/bash
redis-server --daemonize yes --port 6379
nginx -c /home/user/app/nginx.conf
python3 /home/user/app/app.py &
EOF
    chmod +x /home/user/app/start_services.sh

    cat << 'EOF' > /home/user/corpora/clean/transactions.csv
123,456,10.00,Valid Purchase
124,457,3,Another Purchase
125,458,0.01,Small Purchase
EOF

    cat << 'EOF' > /home/user/corpora/evil/anomalies.csv
123,456,-10.00,Valid Purchase
124,457,0,Another Purchase
125,458,abc,Small Purchase
126,459,10.00,Valid Purchase,Extra
abc,456,10.00,Valid Purchase
123,def,10.00,Valid Purchase
127,460,10.00,Special @#$ chars
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
