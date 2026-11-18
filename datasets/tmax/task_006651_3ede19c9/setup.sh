#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest flask

    mkdir -p /home/user/workspace
    cd /home/user/workspace

    cat << 'EOF' > libauth.c
#include <stdio.h>

int generate_token(int seed) {
    return (seed * 1337) ^ 0xDEAD;
}
EOF

    cat << 'EOF' > app.py
from flask import Flask, jsonify
import ctypes
import os

app = Flask(__name__)

# TODO: Load libauth.so and configure the generate_token function
# lib = ...

@app.route('/token/<int:seed>')
def get_token(seed):
    # TODO: Call generate_token and return {"token": result}
    pass

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8000)
EOF

    cat << 'EOF' > migrate.py
import sqlite3
import os

def migrate():
    db_path = '/home/user/workspace/auth.db'
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute('''CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, username TEXT)''')
    c.execute('''INSERT INTO users (username) VALUES ('admin')''')
    conn.commit()
    conn.close()
    print("Migration complete.")

if __name__ == '__main__':
    migrate()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
