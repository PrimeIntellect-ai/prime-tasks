#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest flask

    mkdir -p /home/user/workspace

    cat << 'EOF' > /home/user/workspace/app.py
from flask import Flask, request, redirect, render_template

app = Flask(__name__)

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        # Authentication logic here
        next_url = request.args.get('next')
        if next_url:
            return redirect(next_url)
        return redirect('/dashboard')
    return "Login Page"

if __name__ == '__main__':
    app.run()
EOF

    cat << 'EOF' > /home/user/workspace/access.log
192.168.1.50 - - [10/Oct/2023:13:55:36 -0700] "GET /login?next=/dashboard HTTP/1.1" 200 2326
10.10.10.10 - - [10/Oct/2023:13:56:10 -0700] "GET /login?next=http://evil.com/phish HTTP/1.1" 302 2326
192.168.1.51 - - [10/Oct/2023:13:57:36 -0700] "GET /login?next=https://malicious.org/login HTTP/1.1" 302 2326
172.16.0.5 - - [10/Oct/2023:13:58:00 -0700] "GET /login?next=/profile HTTP/1.1" 200 2326
10.10.10.10 - - [10/Oct/2023:13:59:10 -0700] "POST /login?next=http://evil.com/phish HTTP/1.1" 302 2326
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
