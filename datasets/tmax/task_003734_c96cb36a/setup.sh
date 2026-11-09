#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        g++ \
        make \
        cmake \
        redis-server \
        redis-tools \
        nginx \
        cron \
        curl \
        git

    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create app directory and start services script
    mkdir -p /app
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
service redis-server start
service nginx start
EOF
    chmod +x /app/start_services.sh

    # Configure Nginx
    cat << 'EOF' > /etc/nginx/sites-available/default
server {
    listen 8080;
    location / {
        proxy_pass http://127.0.0.1:9000;
    }
}
EOF

    # Get cpp-httplib
    mkdir -p /home/user/cpp-httplib
    curl -sSL https://raw.githubusercontent.com/yhirose/cpp-httplib/v0.14.1/httplib.h -o /home/user/cpp-httplib/httplib.h

    # Create data directory
    mkdir -p /home/user/data

    # Set permissions
    chmod -R 777 /home/user
