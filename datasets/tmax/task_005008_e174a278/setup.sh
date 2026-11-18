#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl curl
    pip3 install pytest flask requests

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/wordlist.txt
password
123456
admin
qwerty
shadow123
letmein
dragon
football
monkey
EOF

    openssl req -x509 -newkey rsa:2048 -keyout /home/user/key.pem -out /home/user/cert.pem -days 365 -nodes -subj "/C=US/ST=State/L=City/O=Organization/CN=admin-sys-09"

    cat << 'EOF' > /home/user/server.py
from flask import Flask, request, jsonify
import ssl
import logging

log = logging.getLogger('werkzeug')
log.setLevel(logging.ERROR)

app = Flask(__name__)

@app.route('/admin')
def admin():
    auth = request.authorization
    if auth and auth.username == 'admin-sys-09' and auth.password == 'shadow123':
        return jsonify({"secret_flag": "FLAG{TLS_Bruteforce_Master_9921}"})
    return jsonify({"error": "Unauthorized"}), 401

if __name__ == '__main__':
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain('/home/user/cert.pem', '/home/user/key.pem')
    app.run(host='127.0.0.1', port=8443, ssl_context=context)
EOF

    chmod -R 777 /home/user
