#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nmap curl
    pip3 install pytest flask

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/app.py
import base64
from flask import Flask, request, jsonify

app = Flask(__name__)

def encrypt(text):
    encrypted_bytes = bytearray()
    for char in text:
        p = ord(char)
        c = (p * 11 + 17) % 256
        encrypted_bytes.append(c)
    return base64.b64encode(encrypted_bytes).decode('utf-8')

def decrypt(b64_text):
    try:
        encrypted_bytes = base64.b64decode(b64_text)
        decrypted_chars = []
        for c in encrypted_bytes:
            p = ((c - 17) * 163) % 256
            decrypted_chars.append(chr(p))
        return "".join(decrypted_chars)
    except Exception:
        return ""

@app.route('/api/oracle', methods=['GET'])
def oracle():
    plaintext = request.args.get('plaintext', '')
    if not plaintext:
        return jsonify({"error": "Missing plaintext parameter"}), 400
    return jsonify({"encrypted_cookie": encrypt(plaintext)})

@app.route('/api/admin', methods=['GET'])
def admin():
    user_agent = request.headers.get('User-Agent', '')
    if user_agent != 'RedTeam-Evader-v1':
        return jsonify({"error": "WAF Block: Invalid User-Agent"}), 403

    auth_token = request.cookies.get('auth_token')
    if not auth_token:
        return jsonify({"error": "Missing auth_token cookie"}), 401

    user = decrypt(auth_token)
    if user == "administrator_root":
        return jsonify({"flag": "FLAG{lin3ar_crypt4nalys1s_byp4ss_succ3ss}"})
    else:
        return jsonify({"error": f"Unauthorized user: {user}"}), 403

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8005)
EOF

    # Create a startup script to run the Flask app in the background when the container is executed
    cat << 'EOF' > /.singularity.d/env/99-app.sh
#!/bin/sh
python3 /home/user/app.py >/dev/null 2>&1 &
sleep 1
EOF
    chmod +x /.singularity.d/env/99-app.sh

    chmod -R 777 /home/user
