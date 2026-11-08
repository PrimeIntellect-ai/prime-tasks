#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx build-essential curl
    pip3 install pytest flask requests

    mkdir -p /app/corpora/evil /app/corpora/clean
    echo "GGGGGGGGGGGGGGGGGGGG" > /app/corpora/evil/evil_1.txt
    echo "GGGCCCGGGCCCGGGCCCGC" > /app/corpora/evil/evil_2.txt
    echo "AAAAAAAAAAAAAAAAAAAA" > /app/corpora/clean/clean_1.txt
    echo "AATTAATTAATTAATTAATT" > /app/corpora/clean/clean_2.txt
    echo "ATGCATGCATGCATGCATGC" > /app/corpora/clean/clean_3.txt

    cat << 'EOF' > /app/flask_app.py
from flask import Flask, request
import requests
app = Flask(__name__)
@app.route('/submit', methods=['POST'])
def submit():
    seq = request.data.decode('utf-8')
    # AGENT MUST INSERT FILTER CALL HERE
    resp = requests.post('http://127.0.0.1:5001/simulate', data=seq)
    return resp.text, resp.status_code
if __name__ == '__main__':
    app.run(port=5000)
EOF

    cat << 'EOF' > /app/pde_backend.py
from flask import Flask, request
app = Flask(__name__)
@app.route('/simulate', methods=['POST'])
def simulate():
    return "Simulated OK", 200
if __name__ == '__main__':
    app.run(port=5001)
EOF

    cat << 'EOF' > /app/nginx.conf
events {}
http {
    server {
        listen 8080;
        location / {
            proxy_pass http://127.0.0.1:5000;
        }
    }
}
EOF

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
pkill -f flask_app.py
pkill -f pde_backend.py
nginx -s stop || true
nginx -c /app/nginx.conf
python3 /app/flask_app.py &
python3 /app/pde_backend.py &
sleep 2
EOF
    chmod +x /app/start_services.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
