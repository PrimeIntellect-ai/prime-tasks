#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/webapp

    cat << 'EOF' > /home/user/webapp/app.py
import sqlite3
from flask import Flask, request, redirect, render_template

app = Flask(__name__)
db = sqlite3.connect(':memory:', check_same_thread=False)

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        user = request.form.get('username')
        pwd = request.form.get('password')
        if user == 'admin' and pwd == 'admin':
            next_url = request.args.get('next')
            # VULNERABLE: Open Redirect
            return redirect(next_url)
    return "Login Page"

@app.route('/search', methods=['GET'])
def search():
    query = request.args.get('q', '')
    cursor = db.cursor()
    # VULNERABLE: SQL Injection
    cursor.execute("SELECT * FROM items WHERE name = '" + query + "'")
    results = cursor.fetchall()
    return str(results)

if __name__ == '__main__':
    app.run(port=8080)
EOF

    cat << 'EOF' > /home/user/webapp/tokens.txt
42
32051
51908
EOF

    chmod -R 777 /home/user
