#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx expect socat curl netcat-openbsd
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create backend.sh
    cat << 'EOF' > /home/user/backend.sh
#!/bin/bash
echo -n "Enter passphrase to unlock server: "
read -r pass
if [ "$pass" != "admin_secret_99" ]; then
    echo "Access Denied"
    exit 1
fi
echo "Server unlocked. Listening on port 8081..."

# Simulate a server that crashes after 2 requests
for i in 1 2; do
    echo -e "HTTP/1.1 200 OK\r\nContent-Length: 17\r\n\r\nOK_BACKEND_ACTIVE" | nc -l -p 8081 -q 1 > /dev/null
done
echo "Backend crashed."
exit 1
EOF
    chmod +x /home/user/backend.sh

    # Create nginx.conf
    cat << 'EOF' > /home/user/nginx.conf
worker_processes 1;
error_log /home/user/error.log;
pid /home/user/nginx.pid;

events {
    worker_connections 1024;
}

http {
    client_body_temp_path /home/user/client_body;
    proxy_temp_path /home/user/proxy_temp;
    fastcgi_temp_path /home/user/fastcgi_temp;
    uwsgi_temp_path /home/user/uwsgi_temp;
    scgi_temp_path /home/user/scgi_temp;
    access_log /home/user/access.log;

    server {
        listen 8080;
        server_name localhost;

        location / {
            # Intentionally broken port (8082 instead of 8081)
            proxy_pass http://127.0.0.1:8082;
        }
    }
}
EOF

    # Create temp directories
    mkdir -p /home/user/client_body /home/user/proxy_temp /home/user/fastcgi_temp /home/user/uwsgi_temp /home/user/scgi_temp

    chmod -R 777 /home/user
