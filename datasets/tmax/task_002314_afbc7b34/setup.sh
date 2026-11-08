#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server gcc libcurl4-openssl-dev libjansson-dev
    pip3 install pytest flask redis

    mkdir -p /app

    cat << 'EOF' > /app/mock_backup_api.py
from flask import Flask, request, jsonify

app = Flask(__name__)

@app.route('/api/chunks')
def chunks():
    page = int(request.args.get('page', 1))
    if page > 10:
        return jsonify([])
    return jsonify([{"id": page, "type": "node", "status": "active"}])

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    cat << 'EOF' > /app/verify_accuracy.py
import sys
print(1.0)
EOF

    cat << 'EOF' > /app/startup.sh
#!/bin/bash
redis-server --daemonize yes
python3 /app/mock_backup_api.py > /dev/null 2>&1 &
sleep 2
EOF
    chmod +x /app/startup.sh /app/mock_backup_api.py /app/verify_accuracy.py

    # The testing framework might not automatically run startup.sh before initial state tests,
    # so we add a hook to start services if they aren't running.
    echo "/app/startup.sh" >> /etc/bash.bashrc

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
