#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip procps
    pip3 install pytest flask pyjwt

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/weak_passwords.txt
admin123
password
sunflower
charlie
devops2023
supersecret
letmein1
EOF

    cat << 'EOF' > /tmp/rogue_service.py
import logging
from flask import Flask, jsonify, request
import jwt
import sys

app = Flask(__name__)
app.logger.setLevel(logging.ERROR)
log = logging.getLogger('werkzeug')
log.setLevel(logging.ERROR)

SECRET_KEY = "charlie"

@app.route('/guest_token', methods=['GET'])
def get_guest_token():
    token = jwt.encode({"user": "guest", "role": "none"}, SECRET_KEY, algorithm="HS256")
    return jsonify({"token": token})

@app.route('/secure_data', methods=['GET'])
def get_secure_data():
    auth_header = request.headers.get("Authorization")
    if not auth_header or not auth_header.startswith("Bearer "):
        return "Unauthorized", 401

    token = auth_header.split(" ")[1]
    try:
        decoded = jwt.decode(token, SECRET_KEY, algorithms=["HS256"])
        if decoded.get("role") == "admin" and decoded.get("user") == "auditor":
            return "FLAG{devsecops_jwt_audited_8912}", 200
        else:
            return "Forbidden: Admin only", 403
    except jwt.InvalidTokenError:
        return "Invalid token", 401

if __name__ == '__main__':
    # Run on port 9006
    app.run(host='127.0.0.1', port=9006, debug=False)
EOF

    # Ensure the rogue service is running when the container is executed
    cat << 'EOF' > /.singularity.d/env/99-rogue.sh
#!/bin/bash
if ! pgrep -f rogue_service.py > /dev/null; then
    python3 /tmp/rogue_service.py >/dev/null 2>&1 &
    sleep 1
fi
EOF
    chmod +x /.singularity.d/env/99-rogue.sh

    chmod -R 777 /home/user
