#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-pip postgresql redis-server sudo curl

    pip3 install pytest flask psycopg2-binary redis requests pandas

    mkdir -p /app
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
service postgresql start
service redis-server start
nohup python3 /app/app.py > /app/flask.log 2>&1 &
echo "Services started."
EOF
    chmod +x /app/start_services.sh

    cat << 'EOF' > /app/app.py
from flask import Flask, jsonify
app = Flask(__name__)

@app.route('/score/<account_id>')
def score(account_id):
    return jsonify({"score": 0.9 if account_id == "evil_user" else 0.1})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/corpora/clean
    mkdir -p /home/user/corpora/evil

    cat << 'EOF' > /home/user/corpora/clean/clean_1.csv
tx_id,sender,receiver,amount
1,alice,bob,100
EOF

    cat << 'EOF' > /home/user/corpora/evil/evil_1.csv
tx_id,sender,receiver,amount
2,evil_user,accomplice,50000
EOF

    cat << 'EOF' > /home/user/detector.py
import sys
import csv
import psycopg2
import requests
import redis

def process_csv(input_path, output_path):
    pass

if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(1)
    process_csv(sys.argv[1], sys.argv[2])
EOF

    chmod -R 777 /home/user
    chmod -R 777 /app
