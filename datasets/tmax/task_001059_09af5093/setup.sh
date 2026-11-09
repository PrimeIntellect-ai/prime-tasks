#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx sqlite3 curl
    pip3 install pytest flask

    mkdir -p /app/corpora/evil /app/corpora/clean
    mkdir -p /home/user/nginx /home/user/api /home/user/data

    # Create Nginx config
    cat << 'EOF' > /home/user/nginx/nginx.conf
worker_processes 1;
pid /home/user/nginx/nginx.pid;
events {
    worker_connections 1024;
}
http {
    error_log /home/user/nginx/error.log;
    access_log /home/user/nginx/access.log;
    client_body_temp_path /home/user/nginx/client_body;
    proxy_temp_path /home/user/nginx/proxy;
    fastcgi_temp_path /home/user/nginx/fastcgi;
    uwsgi_temp_path /home/user/nginx/uwsgi;
    scgi_temp_path /home/user/nginx/scgi;

    server {
        listen 8080;
        server_name localhost;
        # missing proxy_pass directive here
    }
}
EOF

    # Create Flask app
    cat << 'EOF' > /home/user/api/app.py
from flask import Flask, jsonify
import sqlite3

app = Flask(__name__)
DB_PATH = '/home/user/data/prod.db'

@app.route('/api/health')
def health():
    return jsonify({"status": "ok"})

@app.route('/api/data')
def data():
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('SELECT * FROM dependencies')
    rows = c.fetchall()
    conn.close()
    return jsonify(rows)

if __name__ == '__main__':
    app.run(port=5000)
EOF

    # Create start script
    cat << 'EOF' > /app/start.sh
#!/bin/bash
python3 /home/user/api/app.py &
nginx -c /home/user/nginx/nginx.conf
EOF
    chmod +x /app/start.sh

    # Generate databases and corpora
    python3 -c "
import sqlite3, json, os

def create_db(path, edges):
    conn = sqlite3.connect(path)
    c = conn.cursor()
    c.execute('CREATE TABLE dependencies (id INTEGER PRIMARY KEY, parent_name TEXT, child_name TEXT)')
    for p, ch in edges:
        c.execute('INSERT INTO dependencies (parent_name, child_name) VALUES (?, ?)', (p, ch))
    conn.commit()
    conn.close()

create_db('/home/user/data/prod.db', [('root_node', 'A'), ('A', 'B'), ('B', 'C'), ('C', 'A')])
create_db('/home/user/data/backup.db', [('root_node', 'A'), ('A', 'B'), ('B', 'C'), ('B', 'D')])

for i in range(5):
    with open(f'/app/corpora/evil/evil_{i}.json', 'w') as f:
        json.dump([{'parent': 'A', 'child': 'B'}, {'parent': 'B', 'child': 'A'}], f)
    with open(f'/app/corpora/clean/clean_{i}.json', 'w') as f:
        json.dump([{'parent': 'A', 'child': 'B'}, {'parent': 'A', 'child': 'C'}], f)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
