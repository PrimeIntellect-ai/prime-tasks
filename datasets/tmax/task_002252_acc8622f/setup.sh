#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest flask requests

    mkdir -p /app/logs

    cat << 'EOF' > /app/logs/security.log
[2023-10-24] EventID=1111 User=guest Status=Failed
[2023-10-25] EventID=4421 User=admin Status=AuditMode AuditKey=c2VjcmV0X2NvbXBsaWFuY2Vfc2VlZF85OQ==
[2023-10-26] EventID=2222 User=system Status=OK
EOF

    cat << 'EOF' > /app/legacy_hasher.py
import hashlib

def _obf_func(a, b):
    _t = str(a) + ":" + str(len(b))
    return hashlib.sha256(_t.encode('utf-8')).hexdigest()
EOF

    cat << 'EOF' > /app/ingester.py
from flask import Flask, request, jsonify
import requests

app = Flask(__name__)

@app.route('/ingest', methods=['POST'])
def ingest():
    data = request.get_data()
    # TODO: Calculate X-Audit-Token and add to headers
    headers = {'Content-Type': request.content_type or 'application/json'}

    try:
        resp = requests.post('http://127.0.0.1:5001/validate', data=data, headers=headers)
        return (resp.content, resp.status_code, resp.headers.items())
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

    cat << 'EOF' > /app/validator.py
from flask import Flask, request, jsonify
import requests
import hashlib

app = Flask(__name__)

@app.route('/validate', methods=['POST'])
def validate():
    token = request.headers.get('X-Audit-Token')
    data = request.get_data()

    expected = hashlib.sha256(f"secret_compliance_seed_99:{len(data)}".encode()).hexdigest()
    if token != expected:
        return jsonify({"error": "Invalid or missing token"}), 403

    headers = {'Content-Type': request.content_type or 'application/json'}
    try:
        resp = requests.post('http://127.0.0.1:5002/store', data=data, headers=headers)
        return (resp.content, resp.status_code, resp.headers.items())
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5001)
EOF

    cat << 'EOF' > /app/storage.py
from flask import Flask, request, jsonify

app = Flask(__name__)

@app.route('/store', methods=['POST'])
def store():
    return jsonify({"status": "stored"}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5002)
EOF

    cat << 'EOF' > /app/startup.sh
#!/bin/bash
python3 /app/ingester.py &
python3 /app/validator.py &
python3 /app/storage.py &
wait
EOF

    chmod +x /app/startup.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
