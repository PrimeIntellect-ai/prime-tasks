#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest PyJWT Flask

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/app.py
import os
from flask import Flask, request, jsonify
import jwt

app = Flask(__name__)
# Vulnerability: Hardcoded JWT Secret (CWE-798)
app.config['SECRET_KEY'] = 'SuperSecretForensicsKey123!'

@app.route('/api/run', methods=['POST'])
def run_command():
    token = request.headers.get('Authorization')
    if not token:
        return jsonify({'error': 'Missing token'}), 401
    try:
        data = jwt.decode(token, app.config['SECRET_KEY'], algorithms=["HS256"])
        # Executes payload (Command Injection)
        os.system(data['payload'])
        return jsonify({'status': 'success'})
    except:
        return jsonify({'error': 'Invalid token'}), 403

if __name__ == '__main__':
    app.run(port=8080)
EOF

    cat << 'EOF' > /home/user/auth.log
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VybmFtZSI6Ind3dy1kYXRhIiwicGF5bG9hZCI6IndnZXQgaHR0cDovL21hbGljaW91cy5jb20vc2hlbGwuc2gifQ.QpT8Lp4hO8TfA2qf9oT1qH6gR0cO2QyC4gB9N7r1L_U
EOF

    cat << 'EOF' > /home/user/priv_matrix.txt
root ALL=(ALL:ALL) ALL
admin ALL=(ALL:ALL) ALL
dev ALL=(ALL) NOPASSWD: /usr/bin/systemctl
www-data ALL=(ALL) NOPASSWD: /usr/bin/tar
guest ALL=(ALL) /bin/ls
EOF

    chmod -R 777 /home/user
