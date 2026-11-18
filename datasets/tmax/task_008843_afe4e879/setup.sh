#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx netcat-openbsd curl
    pip3 install pytest

    mkdir -p /home/user/nginx_setup /home/user/backend /home/user/backup

    cat << 'EOF' > /home/user/backend/start.sh
#!/bin/bash
if [ -z "$BACKEND_PORT" ]; then
    echo "Error: BACKEND_PORT is not set." >&2
    exit 1
fi
echo "Starting mock backend on port $BACKEND_PORT..."
while true; do
    echo -e "HTTP/1.1 200 OK\r\nContent-Length: 13\r\n\r\nHello Backend" | nc -l -p $BACKEND_PORT -q 1
done
EOF
    chmod +x /home/user/backend/start.sh

    cat << 'EOF' > /home/user/nginx_setup/nginx.conf
events {
    worker_connections 1024;
}
http {
    server {
        listen 8080;
        location / {
            proxy_pass http://127.0.0.1:8082;
        }
    }
}
EOF

    touch /home/user/.bashrc

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
