#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx curl openssl
    pip3 install pytest flask

    useradd -m -s /bin/bash user || true

    # Create dummy backend
    cat << 'EOF' > /home/user/backend.py
from flask import Flask

app = Flask(__name__)

@app.route('/health')
def health():
    return "OK\n", 200

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    # Create basic nginx conf
    cat << 'EOF' > /home/user/nginx.conf
worker_processes 1;
daemon off;
error_log /home/user/error.log;
pid /home/user/nginx.pid;

events {
    worker_connections 1024;
}

http {
    access_log /home/user/access.log;
    client_body_temp_path /home/user/client_body;
    proxy_temp_path /home/user/proxy;
    fastcgi_temp_path /home/user/fastcgi;
    uwsgi_temp_path /home/user/uwsgi;
    scgi_temp_path /home/user/scgi;

    server {
        listen 8443;
        server_name localhost;

        # Missing SSL directives and location /health block
    }
}
EOF

    mkdir -p /app
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
python3 /home/user/backend.py > /dev/null 2>&1 &
sleep 2
EOF
    chmod +x /app/start_services.sh

    mkdir -p /home/user/client_body /home/user/proxy /home/user/fastcgi /home/user/uwsgi /home/user/scgi

    chmod -R 777 /home/user
    chmod -R 777 /app
