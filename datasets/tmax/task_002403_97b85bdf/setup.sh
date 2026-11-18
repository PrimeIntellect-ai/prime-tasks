#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip nginx socat clamav-daemon curl openssl gcc
pip3 install pytest

# Create required directories
mkdir -p /app/bin /app/certs /app/config /var/uploads

# Set permissions for /var/uploads
chmod 0777 /var/uploads

# Create the oracle reference binary
cat << 'EOF' > /app/bin/oracle_waf_reference.c
#include <stdio.h>
int main() {
    printf("HTTP/1.1 403 Forbidden\n");
    return 0;
}
EOF
gcc /app/bin/oracle_waf_reference.c -o /app/bin/oracle_waf_reference
chmod +x /app/bin/oracle_waf_reference
rm /app/bin/oracle_waf_reference.c

# Generate TLS certificates (simulating expired/invalid certs)
openssl req -x509 -nodes -days 1 -subj "/C=US/O=Test/CN=TestCA" -newkey rsa:2048 -keyout /app/certs/ca.key -out /app/certs/ca.crt
openssl req -x509 -nodes -days 1 -subj "/C=US/O=Test/CN=localhost" -newkey rsa:2048 -keyout /app/certs/server.key -out /app/certs/server.crt

# Create the base nginx.conf
cat << 'EOF' > /app/config/nginx.conf
events {}
http {
    server {
        listen 8443 ssl;
        server_name localhost;

        ssl_certificate /app/certs/server.crt;
        ssl_certificate_key /app/certs/server.key;

        location /upload {
            proxy_pass http://127.0.0.1:8080;
        }
    }
}
EOF

# Create user and set home directory permissions
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
