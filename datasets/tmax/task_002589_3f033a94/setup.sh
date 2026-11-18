#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server gcc
    pip3 install pytest flask redis

    mkdir -p /app/corpus/evil /app/corpus/clean /app/config /app/tools /home/user

    # Create payload decoder
    cat << 'EOF' > /app/tools/payload_decoder.c
#include <stdio.h>
int main() {
    printf("Decoder loaded.\n");
    return 0;
}
EOF
    gcc -o /app/tools/payload_decoder.elf /app/tools/payload_decoder.c
    chmod +x /app/tools/payload_decoder.elf

    # Create Nginx config
    cat << 'EOF' > /app/config/nginx.conf
worker_processes 1;
daemon yes;
events {
    worker_connections 1024;
}
http {
    server {
        listen 8080;
        location / {
            proxy_pass http://127.0.0.1:5000;
        }
    }
}
EOF

    # Create Flask app
    cat << 'EOF' > /app/flask_app.py
from flask import Flask
import redis

app = Flask(__name__)
cache = redis.Redis(host='127.0.0.1', port=6379)

@app.route('/')
def index():
    return "OK"

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    # Create corpus files
    echo -e "GET /?redirect=%25%36%38%25%37%34%25%37%34%25%37%30%25%33%61%25%32%66%25%32%66%25%36%35%25%37%36%25%36%39%25%36%63%25%32%65%25%36%33%25%36%66%25%36%64 HTTP/1.1\r\nHost: localhost\r\n\r\n" > /app/corpus/evil/payload1.req
    echo -e "GET /?redirect=/dashboard HTTP/1.1\r\nHost: localhost\r\n\r\n" > /app/corpus/clean/normal1.req

    # Create pytest wrapper to ensure services are running during tests
    if [ -f /usr/local/bin/pytest ]; then
        mv /usr/local/bin/pytest /usr/local/bin/pytest-real
        cat << 'EOF' > /usr/local/bin/pytest
#!/bin/bash
redis-server --daemonize yes || true
nginx -c /app/config/nginx.conf || true
nohup python3 /app/flask_app.py > /dev/null 2>&1 &
sleep 2
exec /usr/local/bin/pytest-real "$@"
EOF
        chmod +x /usr/local/bin/pytest
    fi

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
