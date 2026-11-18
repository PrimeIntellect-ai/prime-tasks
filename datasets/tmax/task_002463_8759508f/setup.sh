#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install necessary system packages for the task
    apt-get install -y redis-server nginx xxd xz-utils

    # Install Python packages needed for evaluation
    pip3 install redis requests

    # Create the user
    useradd -m -s /bin/bash user || true

    # Create required directories
    mkdir -p /home/user/incoming
    mkdir -p /home/user/artifacts
    mkdir -p /var/lib/nginx /var/log/nginx

    # Generate dummy data
    dd if=/dev/urandom of=/tmp/alpha.raw bs=1M count=1
    dd if=/dev/urandom of=/tmp/beta.raw bs=1M count=1
    xxd -p /tmp/alpha.raw | fold -w 64 > /tmp/alpha.hex
    xxd -p /tmp/beta.raw | fold -w 64 > /tmp/beta.hex

    split -l 5000 /tmp/alpha.hex /home/user/incoming/alpha.part -d -a 2
    split -l 5000 /tmp/beta.hex /home/user/incoming/beta.part -d -a 2

    # Create metadata files in UTF-16LE
    echo "Author: Dr. Turing" | iconv -f UTF-8 -t UTF-16LE > /home/user/incoming/alpha.meta
    echo "Author: Dr. Lovelace" | iconv -f UTF-8 -t UTF-16LE > /home/user/incoming/beta.meta

    # Create trigger files
    touch /home/user/incoming/alpha.done
    touch /home/user/incoming/beta.done

    # Create Nginx configuration
    cat << 'EOF' > /home/user/nginx.conf
worker_processes 1;
daemon on;
pid /tmp/nginx.pid;
events { worker_connections 1024; }
http {
    access_log /tmp/access.log;
    error_log /tmp/error.log;
    server {
        listen 8080;
        server_name localhost;
        location / {
            root /home/user/artifacts;
            autoindex on;
        }
    }
}
EOF

    # Ensure Nginx directories are writable by non-root user
    chmod -R 777 /var/lib/nginx /var/log/nginx

    # Set ownership and permissions
    chown -R user:user /home/user
    chmod -R 777 /home/user
