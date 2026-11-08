#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest flask requests

    mkdir -p /home/user/app /home/user/certs

    # Generate old certificates
    openssl req -x509 -newkey rsa:2048 -keyout /home/user/certs/old_ca.key -out /home/user/certs/old_ca.pem -days 1 -nodes -subj "/CN=OldCA"
    openssl req -newkey rsa:2048 -keyout /home/user/certs/old_server.key -out /home/user/certs/old_server.csr -nodes -subj "/CN=localhost"
    openssl x509 -req -in /home/user/certs/old_server.csr -CA /home/user/certs/old_ca.pem -CAkey /home/user/certs/old_ca.key -CAcreateserial -out /home/user/certs/old_server.crt -days 1

    # Generate new certificates
    openssl req -x509 -newkey rsa:2048 -keyout /home/user/certs/new_ca.key -out /home/user/certs/new_ca.pem -days 365 -nodes -subj "/CN=NewCA"
    openssl req -newkey rsa:2048 -keyout /home/user/certs/new_server.key -out /home/user/certs/new_server.csr -nodes -subj "/CN=localhost"
    openssl x509 -req -in /home/user/certs/new_server.csr -CA /home/user/certs/new_ca.pem -CAkey /home/user/certs/new_ca.key -CAcreateserial -out /home/user/certs/new_server.crt -days 365

    # Create server.py
    cat << 'EOF' > /home/user/app/server.py
import ssl
from flask import Flask, jsonify, make_response

app = Flask(__name__)

@app.route('/webhook', methods=['GET', 'POST'])
def webhook():
    response = make_response(jsonify({"status": "success", "message": "Webhook received"}))
    return response

if __name__ == '__main__':
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    # VULNERABLE: Using old certificates
    context.load_cert_chain('/home/user/certs/old_server.crt', '/home/user/certs/old_server.key')
    app.run(host='0.0.0.0', port=8443, ssl_context=context)
EOF

    # Create client.py
    cat << 'EOF' > /home/user/app/client.py
import requests
import json

def call_webhook():
    url = "https://localhost:8443/webhook"
    try:
        # VULNERABLE: verify=False ignores the certificate chain completely
        response = requests.get(url, verify=False)
        output = {
            "status_code": response.status_code,
            "headers": dict(response.headers),
            "body": response.json()
        }
        print(json.dumps(output))
    except Exception as e:
        print(json.dumps({"error": str(e)}))

if __name__ == "__main__":
    call_webhook()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
