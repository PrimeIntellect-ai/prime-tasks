#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server curl
    pip3 install pytest flask redis pandas

    mkdir -p /home/user/app
    mkdir -p /home/user/corpus/clean
    mkdir -p /home/user/corpus/evil
    mkdir -p /home/user/test_data

    cat << 'EOF' > /home/user/app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
nginx -c /home/user/app/nginx.conf
python3 /home/user/app/app.py &
EOF
    chmod +x /home/user/app/start_services.sh

    cat << 'EOF' > /home/user/app/nginx.conf
# Broken nginx config
worker_processes 1;
events { worker_connections 1024; }
http {
    server {
        listen 80;
        location / {
            return 404;
        }
    }
}
EOF

    cat << 'EOF' > /home/user/app/app.py
# Broken app.py
import os
from flask import Flask, request
import redis

app = Flask(__name__)
# Broken redis connection
r = redis.Redis(host='localhost', port=9999)

@app.route('/api/upload', methods=['POST'])
def upload():
    return "OK", 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5001)
EOF

    cat << 'EOF' > /home/user/app/base_en.csv
string_id|context_tag|text
btn_submit|button|Submit
msg_success|message|Success!
EOF

    cat << 'EOF' > /home/user/corpus/clean/valid_1.csv
string_id|translation
btn_submit|Soumettre
msg_success|Succès!
EOF

    cat << 'EOF' > /home/user/corpus/evil/malformed_newlines.csv
string_id|translation
btn_submit|Soumettre
msg_success|Suc
cès!
EOF

    cat << 'EOF' > /home/user/corpus/evil/xss_payload.csv
string_id|translation
btn_submit|<script>alert(1)</script>
msg_success|Success!
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
