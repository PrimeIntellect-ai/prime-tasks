#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl curl
    pip3 install pytest flask werkzeug

    mkdir -p /home/user/server
    mkdir -p /home/user/intercepted

    # Generate certificates
    cd /home/user/server
    openssl req -new -x509 -days 365 -nodes -out ca.crt -keyout ca.key -subj "/CN=FakeCA"
    openssl req -new -nodes -out server.csr -keyout server.key -subj "/CN=127.0.0.1"
    openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt -days 365
    openssl req -new -nodes -out client.csr -keyout client.key -subj "/CN=Client"
    openssl x509 -req -in client.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out client.crt -days 365

    # Encrypt client key
    openssl rsa -in client.key -aes256 -passout pass:starburst -out client.enc.key

    cp client.enc.key /home/user/intercepted/
    cp client.crt /home/user/intercepted/

    # Create wordlist
    cat << 'EOF' > /home/user/wordlist.txt
apple
banana
orange
grape
strawberry
starburst
blueberry
watermelon
pineapple
mango
EOF

    # Create Flask server
    cat << 'EOF' > /home/user/server/app.py
from flask import Flask, request, Response
import base64
import ssl

app = Flask(__name__)

@app.route('/auth', methods=['GET'])
def auth():
    resp = Response("Authenticated as guest")
    resp.set_cookie('session', base64.b64encode(b'{"role":"guest"}').decode('utf-8'))
    return resp

@app.route('/flag', methods=['POST'])
def flag():
    cookie = request.cookies.get('session')
    if cookie:
        try:
            decoded = base64.b64decode(cookie).decode('utf-8')
            if '"role":"admin"' in decoded:
                return "FLAG{mTLS_byp4ss_4nd_c00k1e_f0rg3ry_succ3ss}"
        except:
            pass
    return "Forbidden", 403

if __name__ == '__main__':
    context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
    context.verify_mode = ssl.CERT_REQUIRED
    context.load_cert_chain(certfile='/home/user/server/server.crt', keyfile='/home/user/server/server.key')
    context.load_verify_locations(cafile='/home/user/server/ca.crt')
    app.run(host='127.0.0.1', port=8443, ssl_context=context)
EOF

    # Ensure the server starts when an interactive shell is spawned
    echo "nohup python3 /home/user/server/app.py > /home/user/server/server.log 2>&1 &" >> /etc/bash.bashrc
    echo "nohup python3 /home/user/server/app.py > /home/user/server/server.log 2>&1 &" >> /etc/profile

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
