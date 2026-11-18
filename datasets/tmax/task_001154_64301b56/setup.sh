#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest flask requests

    mkdir -p /home/user

    # Create the vulnerable Flask app
    cat << 'EOF' > /home/user/app.py
from flask import Flask, request, redirect, make_response

app = Flask(__name__)

@app.route('/login')
def login():
    # Vulnerable open redirect
    next_url = request.args.get('next')
    if next_url:
        return redirect(next_url)
    return redirect('/dashboard')

@app.route('/dashboard')
def dashboard():
    return "Welcome to the dashboard"

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    # Create the access log
    cat << 'EOF' > /home/user/access.log
192.168.1.10 - - [10/Oct/2023:13:55:01 +0000] "GET /login HTTP/1.1" 302 243
10.0.0.5 - - [10/Oct/2023:13:55:12 +0000] "GET /login?next=/profile HTTP/1.1" 302 243
203.0.113.42 - - [10/Oct/2023:13:56:01 +0000] "GET /login?next=http://evil.com/steal HTTP/1.1" 302 243
203.0.113.42 - - [10/Oct/2023:13:56:05 +0000] "GET /login?next=https://malware.org/drop HTTP/1.1" 302 243
192.168.1.15 - - [10/Oct/2023:13:57:00 +0000] "GET /login?next=http://phish.net HTTP/1.1" 404 122
198.51.100.7 - - [10/Oct/2023:14:01:12 +0000] "GET /login?next=https://attacker.com/log HTTP/1.1" 302 243
10.0.0.8 - - [10/Oct/2023:14:05:00 +0000] "GET /login?next=//baddomain.com HTTP/1.1" 302 243
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
