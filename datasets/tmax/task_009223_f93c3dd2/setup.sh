#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl faketime
    pip3 install pytest flask

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/server.py
import os
from flask import Flask, request, redirect, render_template

app = Flask(__name__)

@app.route('/')
def index():
    return "Welcome to the secure portal."

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        # Authentication logic goes here
        target_url = request.args.get('redirect_uri')
        if target_url:
            return redirect(target_url)
        return redirect('/dashboard')
    return render_template('login.html')

if __name__ == '__main__':
    app.run(ssl_context=('/home/user/server.crt', '/home/user/server.key'))
EOF

    faketime '2025-12-01 00:00:00' openssl req -x509 -newkey rsa:2048 -keyout /home/user/server.key -out /home/user/server.crt -days 30 -nodes -subj "/C=US/ST=State/L=City/O=Org/CN=localhost" -set_serial 0x123456789

    chmod -R 777 /home/user
