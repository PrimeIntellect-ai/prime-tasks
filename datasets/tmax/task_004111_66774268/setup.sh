#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        postgresql \
        nginx \
        curl \
        gnupg \
        sudo

    # Install MongoDB
    curl -fsSL https://pgp.mongodb.com/server-7.0.asc | gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg --dearmor
    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-7.0.list
    apt-get update && apt-get install -y mongodb-org

    pip3 install pytest flask psycopg2-binary pymongo

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app
    mkdir -p /home/user/nginx
    mkdir -p /home/user/corpora/clean
    mkdir -p /home/user/corpora/evil

    # Create Flask App
    cat << 'EOF' > /home/user/app/app.py
import os
from flask import Flask, request, jsonify

app = Flask(__name__)

@app.route('/query', methods=['POST'])
def query():
    return jsonify({"status": "success", "data": []})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    # Create run_flask.sh (missing env vars)
    cat << 'EOF' > /home/user/app/run_flask.sh
#!/bin/bash
python3 /home/user/app/app.py
EOF
    chmod +x /home/user/app/run_flask.sh

    # Create nginx.conf (missing proxy_pass)
    cat << 'EOF' > /home/user/nginx/nginx.conf
events {}
http {
    server {
        listen 8080;
        location /query {
            # proxy_pass missing
        }
    }
}
EOF

    # Create start_services.sh
    cat << 'EOF' > /home/user/start_services.sh
#!/bin/bash
service postgresql start
sudo -u postgres psql -c "CREATE USER researcher WITH PASSWORD 'secret';"
sudo -u postgres psql -c "CREATE DATABASE biomed OWNER researcher;"
mongod --fork --logpath /var/log/mongodb.log
nginx -c /home/user/nginx/nginx.conf
/home/user/app/run_flask.sh &
EOF
    chmod +x /home/user/start_services.sh

    # Create corpus files
    cat << 'EOF' > /home/user/corpora/clean/1.json
{"sql_relations": ["patients", "visits"], "join_conditions": ["patients.id = visits.patient_id"]}
EOF

    cat << 'EOF' > /home/user/corpora/evil/1.json
{"sql_relations": ["patients", "visits", "labs"], "join_conditions": ["patients.id = visits.patient_id"]}
EOF

    chmod -R 777 /home/user
