#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx curl
    pip3 install pytest flask

    mkdir -p /app/corpus/clean /app/corpus/evil
    for i in $(seq 1 10); do
        echo "{\"data\": \"clean_payload_$i\"}" > /app/corpus/clean/clean_$i.json
        echo "{\"data\": \"eval('malicious_$i')\"}" > /app/corpus/evil/evil_$i.json
    done

    cat << 'EOF' > /app/backend.py
from flask import Flask, request

app = Flask(__name__)

@app.route('/', defaults={'path': ''}, methods=['GET', 'POST', 'PUT', 'DELETE'])
@app.route('/<path:path>', methods=['GET', 'POST', 'PUT', 'DELETE'])
def catch_all(path):
    return "OK", 200

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
nginx -c /home/user/nginx.conf &
python3 /app/backend.py &
EOF
    chmod +x /app/start_services.sh

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/nginx.conf
events {}
http {
    server {
        listen 8080;
        location / {
            proxy_pass http://127.0.0.1:9999;
        }
    }
}
EOF

    chmod -R 777 /home/user
