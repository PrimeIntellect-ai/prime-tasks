#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server curl
    pip3 install pytest flask redis

    mkdir -p /home/user/app/certs
    mkdir -p /home/user/corpus/clean
    mkdir -p /home/user/corpus/evil

    # Populate clean corpus
    for i in $(seq 1 20); do
        echo "{\"log_data\": \"Safe log entry $i\", \"timestamp\": \"2023-10-01T12:00:00Z\"}" > /home/user/corpus/clean/test${i}.json
    done

    # Populate evil corpus
    for i in $(seq 1 7); do
        echo "{\"log_data\": \"Malicious ../../etc/passwd\", \"timestamp\": \"2023-10-01T12:00:00Z\"}" > /home/user/corpus/evil/test${i}.json
    done
    for i in $(seq 8 14); do
        # > 1024 chars
        LONG_STR=$(python3 -c "print('A'*1025)")
        echo "{\"log_data\": \"$LONG_STR\", \"timestamp\": \"2023-10-01T12:00:00Z\"}" > /home/user/corpus/evil/test${i}.json
    done
    for i in $(seq 15 20); do
        # Malformed JSON
        echo "{\"log_data\": \"Malformed json, \"timestamp\": \"2023-10-01T12:00:00Z\"" > /home/user/corpus/evil/test${i}.json
    done

    # Create broken nginx.conf
    cat << 'EOF' > /home/user/app/nginx.conf
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

    # Create broken app.py
    cat << 'EOF' > /home/user/app/app.py
from flask import Flask, request, jsonify
import redis

app = Flask(__name__)
# Broken redis port
cache = redis.Redis(host='localhost', port=6380)

@app.route('/ingest', methods=['POST'])
def ingest():
    data = request.json
    return jsonify({"status": "received"}), 200

if __name__ == '__main__':
    app.run(port=5000)
EOF

    # Create start.sh
    cat << 'EOF' > /home/user/app/start.sh
#!/bin/bash
redis-server --daemonize yes
python3 /home/user/app/app.py &
nginx -c /home/user/app/nginx.conf &
EOF
    chmod +x /home/user/app/start.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
