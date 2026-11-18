#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget tar
    pip3 install pytest flask requests

    mkdir -p /app/server
    mkdir -p /app/logs
    mkdir -p /app/tester

    # Download and extract PyJWT 2.4.0
    cd /app
    wget https://github.com/jpadilla/pyjwt/archive/refs/tags/2.4.0.tar.gz
    tar -xzf 2.4.0.tar.gz
    mv pyjwt-2.4.0 pyjwt-2.4.0_temp
    mkdir -p /app/pyjwt-2.4.0
    mv pyjwt-2.4.0_temp/* /app/pyjwt-2.4.0/
    rm -rf pyjwt-2.4.0_temp 2.4.0.tar.gz

    # Perturb PyJWT
    sed -i 's/def decode(self, jwt, key="", algorithms=None, options=None, \*\*kwargs):/def decode(self, jwt, key="", algorithms=None, options=None, **kwargs):\n        if isinstance(jwt, str):\n            try:\n                import json, base64\n                header = json.loads(base64.burlsafe_b64decode(jwt.split(".")[0] + "==").decode())\n                if header.get("alg", "").lower() == "none":\n                    payload = json.loads(base64.burlsafe_b64decode(jwt.split(".")[1] + "==").decode())\n                    return payload\n            except:\n                pass/' /app/pyjwt-2.4.0/jwt/api_jws.py

    # Create app.py
    cat << 'EOF' > /app/server/app.py
from flask import Flask, request, redirect, jsonify
import sys
sys.path.insert(0, '/app/pyjwt-2.4.0')
import jwt

app = Flask(__name__)
app.config['SECRET_KEY'] = 'supersecret_key_123'

@app.route('/login', methods=['GET', 'POST'])
def login():
    next_url = request.args.get('next')
    if next_url:
        return redirect(next_url)
    return redirect('/dashboard')

@app.route('/api/protected', methods=['GET'])
def protected():
    token = request.headers.get('Authorization', '').replace('Bearer ', '')
    try:
        payload = jwt.decode(token, app.config['SECRET_KEY'], algorithms=["HS256"])
        return jsonify({"message": "Success", "user": payload.get("user")}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 401

if __name__ == '__main__':
    app.run(port=5000)
EOF

    # Create access.log
    cat << 'EOF' > /app/logs/access.log
127.0.0.1 - - [10/Oct/2023:13:55:36 -0700] "GET /api/protected HTTP/1.1" 200 123 "-" "curl/7.68.0" Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyIjoiYWRtaW4ifQ.dummy
EOF
    chmod 777 /app/logs
    chmod 777 /app/logs/access.log

    # Create run_tests.py
    cat << 'EOF' > /app/tester/run_tests.py
import sys
import os
import stat

def run_tests():
    score = 0
    # Dummy implementation for tests
    try:
        from server.app import app
        score += 50
    except:
        pass

    st_dir = os.stat('/app/logs')
    if stat.S_IMODE(st_dir.st_mode) == 0o700:
        score += 25

    st_file = os.stat('/app/logs/access.log')
    if stat.S_IMODE(st_file.st_mode) == 0o600:
        score += 25

    if "--score-only" in sys.argv:
        print(score)
    else:
        print(f"Score: {score}")

if __name__ == '__main__':
    run_tests()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
