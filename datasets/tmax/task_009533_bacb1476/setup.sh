#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/microservices-config
    mkdir -p /home/user/data

    cd /home/user/microservices-config
    git init

    cat << 'EOF' > nginx.conf
worker_processes 1;
daemon off;
error_log /dev/null;
pid /tmp/nginx.pid;
events {
    worker_connections 1024;
}
http {
    access_log off;
    server {
        listen 8080;
        server_name localhost;

        location /auth {
            proxy_pass http://127.0.0.1:9000;
        }

        location /data {
            proxy_pass http://127.0.0.1:9001;
        }
    }
}
EOF

    cat << 'EOF' > validate.sh
#!/bin/bash
grep -q "proxy_pass http://127.0.0.1:8081" nginx.conf && grep -q "proxy_pass http://127.0.0.1:8082" nginx.conf
EOF
    chmod +x validate.sh

    cat << 'EOF' > /home/user/backup.sh
#!/bin/bash
echo "Backing up..."
EOF
    chmod +x /home/user/backup.sh

    touch /home/user/.bashrc

    chmod -R 777 /home/user
