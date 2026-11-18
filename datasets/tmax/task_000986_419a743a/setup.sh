#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    mkdir -p /home/user/ml_project
    cd /home/user/ml_project

    git init
    git config --global user.email "dev@example.com"
    git config --global user.name "Developer"

    cat << 'EOF' > train_model.py
import sqlite3
import math

# Initial DB config
DB_PASS = "auth_token_xyz987"

def load_data():
    conn = sqlite3.connect('/home/user/ml_project/data.db')
    c = conn.cursor()
    c.execute("SELECT feature, target FROM training_data")
    return c.fetchall()

def train():
    data = load_data()
    w, b = 0.0, 0.0
    lr = 1.0
    epochs = 100

    for _ in range(epochs):
        total_loss = 0
        for x, y in data:
            pred = w * x + b
            error = pred - y
            total_loss += error ** 2
            w -= lr * error * x
            b -= lr * error
        total_loss /= len(data)

    print(f"Final loss: {total_loss}")
    with open('/home/user/diagnostics.log', 'w') as f:
        f.write(f"Loss: {total_loss:.4f}\n")

if __name__ == "__main__":
    train()
EOF

    git add train_model.py
    git commit -m "Initial commit with model logic"

    cat << 'EOF' > train_model.py
import sqlite3
import os
import math

db_pass = os.environ.get('DB_PASSWORD')
if db_pass != 'auth_token_xyz987':
    print("Authentication failed! DB_PASSWORD not set or incorrect.")
    exit(1)

def load_data():
    conn = sqlite3.connect('/home/user/ml_project/data.db')
    c = conn.cursor()
    c.execute("SELECT feature, target FROM training_data")
    return c.fetchall()

def train():
    data = load_data()
    w, b = 0.0, 0.0
    lr = 1.0  # BUG: Learning rate too high
    epochs = 100

    for _ in range(epochs):
        total_loss = 0
        for x, y in data:
            pred = w * x + b
            error = pred - y
            total_loss += error ** 2
            w -= lr * error * x
            b -= lr * error
        total_loss /= len(data)

    print(f"Final loss: {total_loss}")
    with open('/home/user/diagnostics.log', 'w') as f:
        f.write(f"Loss: {total_loss:.4f}\n")

if __name__ == "__main__":
    train()
EOF

    git add train_model.py
    git commit -m "Remove hardcoded password, use env var"

    python3 -c "
import sqlite3
conn = sqlite3.connect('/home/user/ml_project/data.db')
c = conn.cursor()
c.execute('CREATE TABLE training_data (feature REAL, target REAL)')
data = [
    (1.0, 2.0),
    (2.0, 4.0),
    (3.0, 6.0),
    (10.0, -999.0),
    (4.0, 8.0),
    (5.0, 10.0),
    (15.0, -999.0)
]
c.executemany('INSERT INTO training_data VALUES (?, ?)', data)
conn.commit()
conn.close()
"

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
