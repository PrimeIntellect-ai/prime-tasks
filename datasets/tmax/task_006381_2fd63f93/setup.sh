#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/nginx/logs
    mkdir -p /home/user/app/run
    mkdir -p /home/user/capacity_metrics

    cat << 'EOF' > /home/user/nginx/nginx.conf
http {
    server {
        listen 8080;
        location / {
            proxy_pass http://unix:/home/user/app/run/wrong_socket.sock;
        }
    }
}
events {}
EOF

    cat << 'EOF' > /home/user/app/start.sh
#!/bin/bash
gunicorn --bind unix:/home/user/app/run/gunicorn.sock app:app
EOF
    chmod +x /home/user/app/start.sh

    chmod -R 777 /home/user
