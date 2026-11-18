#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server curl gawk coreutils
    pip3 install pytest flask

    # Create user
    useradd -m -s /bin/bash user || true

    # Create required directories
    mkdir -p /app/backup_data
    mkdir -p /app/api

    # Setup Nginx initial config (misconfigured as requested)
    cat << 'EOF' > /etc/nginx/sites-available/default
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    root /var/www/html;
    index index.html index.htm index.nginx-debian.html;

    server_name _;

    location / {
        try_files $uri $uri/ =404;
    }

    location /api/ {
        # Missing proxy_pass
    }

    location /data/ {
        # Wrong root
        root /var/www/html;
    }
}
EOF

    # Setup Redis initial config (misconfigured as requested)
    cat << 'EOF' > /etc/redis/redis.conf
port 0
unixsocket /var/run/redis/redis-server.sock
unixsocketperm 700
daemonize yes
EOF

    # Setup Python API script
    cat << 'EOF' > /app/api/app.py
from flask import Flask, jsonify
app = Flask(__name__)

@app.route('/api/status')
def status():
    return jsonify({"status": "ok", "service": "backup_api"})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    # Create dummy data for tests
    echo "dummy data" > /app/backup_data/test.dat

    # Setup Oracle script
    cat << 'EOF' > /app/oracle_archiver.sh
#!/bin/bash
while IFS= read -r filename; do
    [ -z "$filename" ] && continue

    # Fetch and convert metadata
    raw_meta=$(redis-cli --raw GET "file_meta:${filename}")
    utf8_meta=$(echo -n "$raw_meta" | iconv -f UTF-16LE -t UTF-8)

    # Concurrent log append
    (
        flock -x 200
        echo "[ARCHIVED] ${filename}" >> /tmp/backup_audit.log
    ) 200>/tmp/audit.lock

    # Fetch payload
    payload=$(curl -s "http://127.0.0.1/data/${filename}")

    # Output strictly
    echo "---BEGIN_RECORD---"
    echo "FILE: ${filename}"
    echo "META: ${utf8_meta}"
    echo "PAYLOAD:"
    echo -n "$payload"
    echo "" # newline after payload
    echo "---END_RECORD---"
done
EOF
    chmod +x /app/oracle_archiver.sh

    chmod -R 777 /home/user
