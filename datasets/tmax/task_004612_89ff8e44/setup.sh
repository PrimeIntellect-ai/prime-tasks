#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx socat curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/nginx/logs
    mkdir -p /home/user/app
    mkdir -p /home/user/scripts
    ln -s /tmp/nonexistent_dir /home/user/app/sockets

    cat << 'EOF' > /home/user/nginx/nginx.conf
worker_processes 1;
pid /home/user/nginx/nginx.pid;
error_log /home/user/nginx/logs/error.log info;

events {
    worker_connections 1024;
}

http {
    access_log /home/user/nginx/logs/access.log;

    server {
        listen 127.0.0.1:8080;

        location / {
            proxy_pass http://unix:/home/user/app/sockets/backend.sock;
        }
    }
}
EOF

    cat << 'EOF' > /home/user/app/start_backend.sh
#!/bin/bash
# Missing umask or permission setting

if [ -z "$BACKEND_SOCKET" ]; then
    echo "Error: BACKEND_SOCKET is not set."
    exit 1
fi

# Remove stale socket
rm -f "$BACKEND_SOCKET"

# Start listening
socat UNIX-LISTEN:"$BACKEND_SOCKET",fork EXEC:"/home/user/app/response.sh" &
EOF

    cat << 'EOF' > /home/user/app/response.sh
#!/bin/bash
printf "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nBackend operational."
EOF

    chmod +x /home/user/app/start_backend.sh /home/user/app/response.sh

    chmod -R 777 /home/user
