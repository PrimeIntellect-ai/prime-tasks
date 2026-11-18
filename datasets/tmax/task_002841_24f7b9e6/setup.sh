#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak procps
    pip3 install pytest flask werkzeug requests

    mkdir -p /app
    espeak -w /app/intercepted_comms.wav "The new administration portal has been moved to slash hidden underscore admin underscore 77, and the default username is auditor."

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/vulnerable_app.py
from flask import Flask, request, make_response
import subprocess

app = Flask(__name__)

@app.route('/hidden_admin_77/diag')
def diag():
    target = request.args.get('target', '127.0.0.1')
    token = "SUPER_SECRET_SSH_TOKEN_999"

    # Insecurely pass token via command line args to a background process
    subprocess.Popen(["python3", "-c", "import time, sys; time.sleep(5)", token])

    # Command injection vulnerability
    try:
        out = subprocess.check_output(f"ping -c 1 {target}", shell=True)
    except:
        out = b"ping error"

    resp = make_response(out)
    # Insecure cookie creation
    resp.set_cookie('session', 'admin_session')
    return resp

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    cat << 'EOF' > /app/grade_security.py
import sys

def grade(file_path):
    try:
        with open(file_path, 'r') as f:
            code = f.read()

        score = 0.0
        # Check command injection fix
        if "shell=True" not in code and "subprocess" in code:
            score += 0.4

        # Check cookie security
        if "httponly=True" in code.lower() and "secure=True" in code.lower():
            score += 0.3

        # Check env variable usage for token
        if "env=" in code or "os.environ" in code:
            score += 0.3

        print(round(score, 1))
    except Exception:
        print(0.0)

if __name__ == '__main__':
    if len(sys.argv) > 1:
        grade(sys.argv[1])
    else:
        print(0.0)
EOF

    chmod -R 777 /app
    chmod -R 777 /home/user
