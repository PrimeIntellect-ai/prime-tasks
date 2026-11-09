#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/audit
    cd /home/user/audit

    # 1. Create wordlist
    cat << 'EOF' > wordlist.txt
apple
hunter2
admin2023
qwerty
password123
letmein99
spring2024
EOF

    # 2. Create users.db
    python3 -c "
import sqlite3, hashlib
conn = sqlite3.connect('users.db')
c = conn.cursor()
c.execute('CREATE TABLE users (username TEXT, password_hash TEXT)')
users = [('admin', 'admin2023'), ('alice', 'hunter2'), ('bob', 'qwerty')]
for u, p in users:
    h = hashlib.md5(p.encode()).hexdigest()
    c.execute('INSERT INTO users VALUES (?, ?)', (u, h))
conn.commit()
conn.close()
"

    # 3. Create server.py
    cat << 'EOF' > server.py
import sqlite3
from flask import Flask, request

app = Flask(__name__)

@app.route('/user')
def get_user():
    user_id = request.args.get('id')
    conn = sqlite3.connect('users.db')
    cursor = conn.cursor()
    # Vulnerable to SQLi
    query = f"SELECT * FROM users WHERE id = {user_id}"
    cursor.execute(query)
    result = cursor.fetchall()
    return str(result)

@app.route('/greet')
def greet():
    name = request.args.get('name', 'Guest')
    # Vulnerable to XSS
    return f"<html><body><h1>Hello, {name}!</h1></body></html>"

if __name__ == '__main__':
    app.run()
EOF

    # 4. Create messages.txt
    cat << 'EOF' > messages.txt
Hello admin, my payment failed. My card is 4111-2222-3333-4444. Can you check?
Also, my backup card 5555-6666-7777-8888 is expiring soon.
Thanks!
EOF

    # 5. Create manifest.sha256
    sha256sum wordlist.txt users.db server.py messages.txt > manifest.sha256

    # 6. Tamper with messages.txt after hashing
    echo "P.S. Call me back." >> messages.txt

    chmod -R 777 /home/user
