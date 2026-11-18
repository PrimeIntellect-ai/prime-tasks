#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest flask

    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/app.py
from flask import Flask, request, jsonify

app = Flask(__name__)

# The secret key is stored elsewhere, but we know it's 4 bytes
SECRET_KEY_LEN = 4

def generate_token(role):
    # Weak custom cryptography for token generation
    pass # Implementation hidden from source, but concept is XOR

@app.route('/')
def index():
    return "Welcome to the site!"

@app.route('/admin')
def admin():
    token = request.cookies.get('auth_token')
    if not token:
        return jsonify({"error": "Unauthorized"}), 401
    return "Admin Panel"

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

    cat << 'EOF' > /home/user/app/network_policy.json
{
  "firewall_rules": [
    {
      "route": "/",
      "action": "ALLOW",
      "source_ip": "0.0.0.0/0"
    },
    {
      "route": "/admin",
      "action": "DROP",
      "source_ip": "*"
    }
  ]
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
