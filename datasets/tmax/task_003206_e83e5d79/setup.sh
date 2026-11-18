#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx curl openssl
    pip3 install pytest flask

    # Create directories
    mkdir -p /app/nginx /app/flask /app/bin /app/certs /app/corpus/clean /app/corpus/evil

    # Generate Certificates
    openssl req -new -x509 -days 365 -nodes -out /app/certs/ca.crt -keyout /app/certs/ca.key -subj "/CN=MyCA"
    openssl req -new -nodes -out /app/certs/server.csr -keyout /app/certs/server.key -subj "/CN=127.0.0.1"
    openssl x509 -req -in /app/certs/server.csr -CA /app/certs/ca.crt -CAkey /app/certs/ca.key -CAcreateserial -out /app/certs/server.crt -days 365
    openssl req -new -nodes -out /app/certs/client.csr -keyout /app/certs/client.key -subj "/CN=MyClient"
    openssl x509 -req -in /app/certs/client.csr -CA /app/certs/ca.crt -CAkey /app/certs/ca.key -CAcreateserial -out /app/certs/client.crt -days 365

    # Create Python Bytecode
    cat << 'EOF' > /app/bin/token_generator.py
def generate_token(url: str) -> str:
    key = "N3tw0rkS3cur1tyK3y"
    encrypted = bytes(ord(url[i]) ^ ord(key[i % len(key)]) for i in range(len(url)))
    return encrypted.hex()
EOF
    python3 -c "import py_compile; py_compile.compile('/app/bin/token_generator.py', cfile='/app/bin/token_generator.pyc')"
    rm /app/bin/token_generator.py

    # Generate Corpus
    python3 -c '
import os
def generate_token(url: str) -> str:
    key = "N3tw0rkS3cur1tyK3y"
    encrypted = bytes(ord(url[i]) ^ ord(key[i % len(key)]) for i in range(len(url)))
    return encrypted.hex()

with open("/app/corpus/clean/clean1.txt", "w") as f: f.write(generate_token("https://internal.corp.local/home"))
with open("/app/corpus/clean/clean2.txt", "w") as f: f.write(generate_token("https://internal.corp.local/settings"))
with open("/app/corpus/evil/evil1.txt", "w") as f: f.write(generate_token("http://evil.attacker.com/phish"))
with open("/app/corpus/evil/evil2.txt", "w") as f: f.write(generate_token("https://internal.corp.local.evil.com/"))
with open("/app/corpus/evil/evil3.txt", "w") as f: f.write("invalid_hex_string_xyz")
'

    # Create Nginx Config
    cat << 'EOF' > /app/nginx/nginx.conf
events {}
http {
    server {
        listen 8443 ssl;
        ssl_certificate /app/certs/server.crt;
        ssl_certificate_key /app/certs/server.key;

        location / {
            proxy_pass http://127.0.0.1:5000;
        }
    }
}
EOF

    # Create Flask App
    cat << 'EOF' > /app/flask/app.py
from flask import Flask, request, redirect, abort
import subprocess, tempfile, os

app = Flask(__name__)

@app.route('/login')
def login():
    token = request.args.get('token')
    if not token:
        return abort(400)
    # TODO: Validate token using /home/user/filter.py and decrypt URL
    # Currently just redirects blindly to internal.corp.local as a placeholder
    return redirect("https://internal.corp.local/dashboard")

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    # Create Start Script
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
nginx -c /app/nginx/nginx.conf
python3 /app/flask/app.py &
EOF
    chmod +x /app/start_services.sh

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
