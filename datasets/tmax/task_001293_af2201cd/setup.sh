#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl
    pip3 install pytest flask requests

    mkdir -p /app/log_service
    mkdir -p /app/auth_service

    cat << 'EOF' > /app/log_service/app.py
from flask import Flask, jsonify

app = Flask(__name__)

@app.route('/logs', methods=['GET'])
def get_logs():
    return jsonify([
        {"tx": "T1", "waiting_for": "T2"},
        {"tx": "T2", "waiting_for": "T3"},
        {"tx": "T3", "waiting_for": "T1"},
        {"tx": "T4", "waiting_for": "T5"},
        {"tx": "T5", "waiting_for": "T4"},
        {"tx": "T8", "waiting_for": "T9"},
        {"tx": "T9", "waiting_for": "T10"},
        {"tx": "T10", "waiting_for": "T11"},
        {"tx": "T11", "waiting_for": "T8"},
        {"tx": "T20", "waiting_for": "T21"},
        {"tx": "T21", "waiting_for": "T20"},
        {"tx": "T30", "waiting_for": "T31"},
        {"tx": "T31", "waiting_for": "T32"},
        {"tx": "T32", "waiting_for": "T33"},
        {"tx": "T33", "waiting_for": "T34"},
        {"tx": "T34", "waiting_for": "T30"},
        {"tx": "T100", "waiting_for": "T101"}
    ])

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8001)
EOF

    cat << 'EOF' > /app/log_service/start.sh
#!/bin/bash
nohup python3 /app/log_service/app.py > /app/log_service/log.txt 2>&1 &
EOF
    chmod +x /app/log_service/start.sh

    cat << 'EOF' > /app/auth_service/app.py
from flask import Flask, request

app = Flask(__name__)

@app.route('/validate', methods=['POST'])
def validate():
    data = request.get_json(force=True, silent=True) or {}
    if data.get('token') == 'audit_sec_9942':
        return '', 200
    return '', 403

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8002)
EOF

    cat << 'EOF' > /app/auth_service/start.sh
#!/bin/bash
nohup python3 /app/auth_service/app.py > /app/auth_service/log.txt 2>&1 &
EOF
    chmod +x /app/auth_service/start.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
