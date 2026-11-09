#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest flask

mkdir -p /home/user/webapp /home/user/evidence

cat << 'EOF' > /home/user/webapp/app.py
from flask import Flask, request, redirect, url_for

app = Flask(__name__)

@app.route('/login', methods=['POST'])
def login():
    # Authentication logic goes here (mocked)
    user_authenticated = True

    if user_authenticated:
        next_url = request.form.get('next')
        if next_url:
            return redirect(next_url)
        return redirect('/dashboard')
    return "Login Failed", 401

@app.route('/dashboard')
def dashboard():
    return "Welcome to the dashboard!"

if __name__ == '__main__':
    app.run(port=8080)
EOF

cat << 'EOF' > /home/user/evidence/beacon.c
#include <stdio.h>
#include <unistd.h>

const char* c2_address = "203.0.113.85";

int main() {
    printf("Beaconing to C2...\n");
    // simulated beacon activity
    return 0;
}
EOF

gcc /home/user/evidence/beacon.c -o /home/user/evidence/beacon
rm /home/user/evidence/beacon.c

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
