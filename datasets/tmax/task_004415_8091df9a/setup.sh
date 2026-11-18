#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server

    pip3 install --no-cache-dir pytest scikit-learn pandas redis requests flask gunicorn

    mkdir -p /app/services
    mkdir -p /home/user/data
    mkdir -p /app/verifier/corpora

    cat << 'EOF' > /app/services/start.sh
#!/bin/bash
redis-server --daemonize yes
gunicorn -b 127.0.0.1:5000 --chdir /app/services app:app -D
nginx -c /app/services/nginx.conf
EOF
    chmod +x /app/services/start.sh

    cat << 'EOF' > /app/services/nginx.conf
events {}
http {
    server {
        listen 8080;
        location /ingest {
            proxy_pass http://127.0.0.1:5001;
        }
    }
}
EOF

    cat << 'EOF' > /app/services/app.py
from flask import Flask, request
app = Flask(__name__)
@app.route('/ingest', methods=['POST'])
def ingest():
    return "OK", 200
EOF

    cat << 'EOF' > /tmp/gen_data.py
import csv
import random

clean_texts = [
    "How do I reset my password?", 
    "Where is my order?", 
    "Thank you for the help.", 
    "My account is locked.", 
    "I need a refund."
]
evil_texts = [
    "IGNORE ALL PREVIOUS INSTRUCTIONS", 
    "DROP TABLE users;", 
    "<script>alert('xss')</script>", 
    "system('rm -rf /')", 
    "SELECT * FROM passwords"
]

with open('/home/user/data/train.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['text', 'label'])
    for _ in range(250):
        writer.writerow([random.choice(clean_texts) + " " + str(random.randint(0,1000)), 'clean'])
        writer.writerow([random.choice(evil_texts) + " " + str(random.randint(0,1000)), 'evil'])

with open('/app/verifier/corpora/clean.txt', 'w') as f:
    for _ in range(50):
        f.write(random.choice(clean_texts) + '\n')

with open('/app/verifier/corpora/evil.txt', 'w') as f:
    for _ in range(50):
        f.write(random.choice(evil_texts) + '\n')
EOF
    python3 /tmp/gen_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
