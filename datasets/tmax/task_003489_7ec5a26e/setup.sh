#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ cron nginx redis-server curl jq nlohmann-json3-dev
    pip3 install pytest flask

    mkdir -p /app/corpus/clean /app/corpus/evil /var/log/nginx

    cat << 'EOF' > /app/corpus/clean/log1.json
{"status": 200, "bytes": 5000}
{"status": 200, "bytes": 5000}
{"status": 404, "bytes": 12000}
{"status": 200, "bytes": 5000}
{"status": 200, "bytes": 5000}
{"status": 500, "bytes": 15000}
{"status": 200, "bytes": 5000}
{"status": 200, "bytes": 5000}
{"status": 200, "bytes": 5000}
{"status": 200, "bytes": 5000}
EOF

    cat << 'EOF' > /app/corpus/evil/log1.json
{"status": 200, "bytes": 500}
{"status": 500, "bytes": 20000}
{"status": 500, "bytes": 20000}
{"status": 403, "bytes": 20000}
{"status": 502, "bytes": 20000}
{"status": 200, "bytes": 20000}
{"status": 200, "bytes": 20000}
{"status": 200, "bytes": 20000}
{"status": 200, "bytes": 20000}
{"status": 200, "bytes": 20000}
EOF

    cat << 'EOF' > /app/backend.py
from flask import Flask
app = Flask(__name__)
@app.route('/')
def hello():
    return "Hello"
if __name__ == '__main__':
    app.run(port=8081)
EOF

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
service nginx start
service redis-server start
python3 /app/backend.py &
EOF
    chmod +x /app/start_services.sh

    useradd -m -s /bin/bash user || true
    chown -R user:user /app/corpus
    chmod -R 777 /home/user
