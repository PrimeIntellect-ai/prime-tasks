#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx curl procps
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/nginx/logs
    mkdir -p /home/user/nginx/temp/client_body
    mkdir -p /home/user/nginx/temp/proxy
    mkdir -p /home/user/nginx/temp/fastcgi
    mkdir -p /home/user/nginx/temp/uwsgi
    mkdir -p /home/user/nginx/temp/scgi
    mkdir -p /home/user/backend
    touch /home/user/.bash_profile

    cat << 'EOF' > /home/user/nginx/nginx.conf
worker_processes 1;
pid /home/user/nginx/nginx.pid;
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
    error_log /home/user/nginx/logs/error.log;

    server {
        listen 8080;
        server_name localhost;

        location / {
            # Typo in proxy pass, and likely wrong port
            proxy_pass http://127.0.0.1:9999;
        }
    }
}
EOF

    cat << 'EOF' > /home/user/backend/run.sh
#!/bin/bash
source /home/user/.bash_profile

if [ -z "$BACKEND_PORT" ]; then
    echo "Error: BACKEND_PORT environment variable is not set."
    exit 1
fi

if [ ! -d "/home/user/backend/cache" ]; then
    echo "Error: Directory /home/user/backend/cache does not exist."
    exit 1
fi

echo "Hello from the backend!" > /home/user/backend/cache/index.html
cd /home/user/backend/cache

# Start a simple HTTP server in the background
nohup python3 -m http.server $BACKEND_PORT > /home/user/backend/backend.log 2>&1 &
echo $! > /home/user/backend/backend.pid
echo "Backend started on port $BACKEND_PORT"
EOF

    chmod +x /home/user/backend/run.sh

    chown -R user:user /home/user
    chmod -R 777 /home/user
