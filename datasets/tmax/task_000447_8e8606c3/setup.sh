#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git strace curl
    pip3 install pytest flask

    # Create app directory
    mkdir -p /home/user/app
    cd /home/user/app

    # Create math_engine.py with buggy formula
    cat << 'EOF' > math_engine.py
def compute(alpha, beta, salt, n):
    if n == 0: return 0
    if n == 1: return 1
    A_prev2 = 0
    A_prev1 = 1
    for _ in range(2, n + 1):
        # BUG: Incorrect formula (should be alpha * A_prev1 + beta * A_prev2 + salt)
        A_curr = alpha * A_prev1 - beta * A_prev2
        A_prev2 = A_prev1
        A_prev1 = A_curr
    return A_curr
EOF

    # Create server.py with FD leak
    cat << 'EOF' > server.py
import os
from flask import Flask, request, jsonify
from dotenv import load_dotenv
import math_engine

load_dotenv()
app = Flask(__name__)

def transcribe_audio(audio_bytes):
    # Dummy transcription that returns 3 and 5 for the test
    return 3, 5

@app.route('/process', methods=['POST'])
def process():
    # BUG: File descriptor leak
    f = open('/dev/urandom', 'rb')
    f.read(1)

    salt_str = os.environ.get('SECRET_SALT')
    if not salt_str:
        return jsonify({"error": "Missing SECRET_SALT"}), 500
    salt = int(salt_str)

    audio_data = request.get_data()
    alpha, beta = transcribe_audio(audio_data)

    result = math_engine.compute(alpha, beta, salt, 100)
    return jsonify({"result": result})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF

    # Setup git repo with forensics challenge
    git init
    git config user.email "dev@example.com"
    git config user.name "Dev"

    echo "SECRET_SALT=42" > .env
    git add .env
    git commit -m "Initial commit with config"

    rm .env
    git add .env
    git commit -m "Remove sensitive config"

    git add server.py math_engine.py
    git commit -m "Add source code"

    # Create audio test file
    mkdir -p /app
    echo "RIFF....WAVEfmt ........" > /app/test_audio.wav

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
