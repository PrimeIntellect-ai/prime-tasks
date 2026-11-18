#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx curl
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/nginx/logs
    mkdir -p /home/user/nginx/temp
    mkdir -p /home/user/app
    mkdir -p /home/user/scripts
    mkdir -p /home/user/logs
    mkdir -p /home/user/mail

    # Create backend script
    cat << 'EOF' > /home/user/app/backend.sh
#!/bin/bash
echo "Starting backend on port 8081..."
# A simple mock HTTP server using python
python3 -m http.server 8081 --bind 127.0.0.1
EOF
    chmod +x /home/user/app/backend.sh

    # Create nginx config with the typo
    cat << 'EOF' > /home/user/nginx/nginx.conf
worker_processes 1;
pid /home/user/nginx/nginx.pid;
error_log /home/user/nginx/logs/error.log;

events {
    worker_connections 1024;
}

http {
    client_body_temp_path /home/user/nginx/temp/client_body;
    proxy_temp_path /home/user/nginx/temp/proxy;
    fastcgi_temp_path /home/user/nginx/temp/fastcgi;
    uwsgi_temp_path /home/user/nginx/temp/uwsgi;
    scgi_temp_path /home/user/nginx/temp/scgi;

    access_log /home/user/nginx/logs/access.log;

    server {
        listen 8080;
        server_name localhost;

        location / {
            proxy_pass http://127.0.0.1:8082; # TYPO HERE, should be 8081
        }
    }
}
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
