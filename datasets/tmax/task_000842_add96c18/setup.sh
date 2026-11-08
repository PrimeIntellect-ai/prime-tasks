#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server
    pip3 install pytest flask redis requests

    mkdir -p /app/data/corpus_clean
    mkdir -p /app/data/corpus_evil

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
python3 /app/emitter.py &
python3 /app/sink.py &
EOF
    chmod +x /app/start_services.sh

    cat << 'EOF' > /app/emitter.py
from flask import Flask
app = Flask(__name__)
if __name__ == '__main__':
    app.run(port=8080)
EOF

    cat << 'EOF' > /app/sink.py
from flask import Flask
app = Flask(__name__)
if __name__ == '__main__':
    app.run(port=9090)
EOF

    echo '{"id": "123", "timestamp": "2023-01-01T00:00:00Z", "host": "host-1", "cpu_usage": 50.0}' > /app/data/corpus_clean/test.jsonl
    echo '{"id": "invalid", "timestamp": "bad", "host": "host 1", "cpu_usage": 150.0}' > /app/data/corpus_evil/test.jsonl

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
