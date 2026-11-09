#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip nginx redis-server
pip3 install pytest redis requests

# Configure Nginx to listen on 8080
sed -i 's/listen 80 default_server;/listen 8080 default_server;/g' /etc/nginx/sites-available/default
sed -i 's/listen \[::\]:80 default_server;/listen \[::\]:8080 default_server;/g' /etc/nginx/sites-available/default

mkdir -p /app/corpora/clean
mkdir -p /app/corpora/evil
mkdir -p /var/www/html

cat << 'EOF' > /var/www/html/config.json
{"forbidden_tags": ["<script>", "<iframe>", "<object>"]}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
