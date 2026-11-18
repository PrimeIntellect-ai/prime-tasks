#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx socat curl
    pip3 install pytest

    mkdir -p /app/vulnerable_stack/bin
    mkdir -p /app/vulnerable_stack/cgi-bin
    mkdir -p /app/vulnerable_stack/logs

    touch /app/vulnerable_stack/bin/auth_helper
    chmod 4755 /app/vulnerable_stack/bin/auth_helper

    touch /app/vulnerable_stack/bin/updater
    chmod 777 /app/vulnerable_stack/bin/updater

    cat << 'EOF' > /app/vulnerable_stack/cgi-bin/login.cgi
#!/bin/bash
# Parse query string manually for simplicity
NEXT_URL=$(echo "$QUERY_STRING" | grep -oP '(?<=next=)[^&]+')

echo "Status: 302 Found"
echo "Location: $NEXT_URL"
echo ""
EOF
    chmod +x /app/vulnerable_stack/cgi-bin/login.cgi

    cat << 'EOF' > /app/vulnerable_stack/nginx.conf
worker_processes 1;
pid /tmp/nginx.pid;
events {
    worker_connections 1024;
}
http {
    access_log /app/vulnerable_stack/logs/access.log;
    error_log /app/vulnerable_stack/logs/error.log;
    server {
        listen 8080;
        server_name localhost;

        location / {
            proxy_pass http://127.0.0.1:8082;
        }
    }
}
EOF

    cat << 'EOF' > /app/vulnerable_stack/start.sh
#!/bin/bash
nginx -c /app/vulnerable_stack/nginx.conf &
socat TCP-LISTEN:8081,fork,reuseaddr EXEC:/app/vulnerable_stack/cgi-bin/login.cgi &
python3 -m http.server 8082 --directory /app/vulnerable_stack &
EOF
    chmod +x /app/vulnerable_stack/start.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
