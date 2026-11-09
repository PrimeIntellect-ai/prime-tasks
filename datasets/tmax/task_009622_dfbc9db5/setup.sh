#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip openssl curl nmap
pip3 install pytest flask requests

mkdir -p /home/user/certs

# Generate certificates
openssl req -x509 -newkey rsa:4096 -keyout /home/user/certs/ca.key -out /home/user/ca.crt -days 365 -nodes -subj "/C=US/ST=State/L=City/O=Org/CN=InternalCA"
openssl req -newkey rsa:4096 -keyout /home/user/certs/server.key -out /home/user/certs/server.csr -nodes -subj "/C=US/ST=State/L=City/O=Org/CN=127.0.0.1"
echo "subjectAltName=IP:127.0.0.1" > /home/user/certs/extfile.cnf
openssl x509 -req -in /home/user/certs/server.csr -CA /home/user/ca.crt -CAkey /home/user/certs/ca.key -CAcreateserial -out /home/user/certs/server.crt -days 365 -extfile /home/user/certs/extfile.cnf

# Create the API server
cat << 'EOF' > /home/user/api_server.py
from flask import Flask, request, jsonify
import base64
import json
import hashlib

app = Flask(__name__)

SECRET_DATA = "SEC-9988-FLAG-2023"
SECRET_HASH = hashlib.sha256(SECRET_DATA.encode()).hexdigest()

@app.route('/admin/data', methods=['GET'])
def admin_data():
    auth_header = request.headers.get('Authorization')
    if not auth_header or not auth_header.startswith('Bearer '):
        return jsonify({"error": "Unauthorized"}), 401

    token = auth_header.split(' ')[1]
    parts = token.split('.')
    if len(parts) != 3:
        return jsonify({"error": "Invalid token format"}), 401

    try:
        # Pad base64 strings
        header_b64 = parts[0] + '=' * (-len(parts[0]) % 4)
        payload_b64 = parts[1] + '=' * (-len(parts[1]) % 4)

        header = json.loads(base64.urlsafe_b64decode(header_b64))
        payload = json.loads(base64.urlsafe_b64decode(payload_b64))

        # Vulnerable check: if alg is none, accept without signature verification
        if header.get('alg', '').lower() == 'none':
            if payload.get('role') == 'admin':
                return jsonify({"data": SECRET_DATA, "sha256": SECRET_HASH})
            else:
                return jsonify({"error": "Forbidden"}), 403
        else:
            # Fake validation for anything else
            return jsonify({"error": "Invalid signature"}), 401

    except Exception as e:
        return jsonify({"error": str(e)}), 400

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8443, ssl_context=('/home/user/certs/server.crt', '/home/user/certs/server.key'))
EOF

# Create a startup script for the server
cat << 'EOF' > /home/user/start_server.sh
#!/bin/bash
if ! pgrep -f api_server.py > /dev/null; then
    python3 /home/user/api_server.py > /dev/null 2>&1 &
    sleep 1
fi
EOF
chmod +x /home/user/start_server.sh

# Ensure the server starts when a bash shell is opened
echo "/home/user/start_server.sh" >> /etc/bash.bashrc

# Create the user
useradd -m -s /bin/bash user || true
echo "/home/user/start_server.sh" >> /home/user/.bashrc

# Set permissions
chown -R user:user /home/user
chmod -R 777 /home/user
