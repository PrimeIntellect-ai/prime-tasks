#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip openssl tar gzip coreutils
pip3 install pytest

mkdir -p /home/user/deploy_source/app
mkdir -p /home/user/deploy_source/certs
cat << 'EOF' > /home/user/deploy_source/nginx.conf
server {
    listen 443 ssl;
    server_name secure.internal.dev;
    add_header Content-Security-Policy "default-src *";
    location / {
        root /app;
    }
}
EOF

cat << 'EOF' > /home/user/deploy_source/app/config.json
{"db_password": "super_secret_db_pass"}
EOF

cat << 'EOF' > /home/user/deploy_source/app/index.html
<html><body>Hello Secure World</body></html>
EOF

chmod 777 /home/user/deploy_source/app/config.json
chmod 777 /home/user/deploy_source/app/index.html
chmod 777 /home/user/deploy_source/app

cd /home/user/deploy_source
tar -czf /home/user/deploy_bundle.tar.gz nginx.conf app certs
openssl enc -aes-256-cbc -pbkdf2 -salt -in /home/user/deploy_bundle.tar.gz -out /home/user/deploy_bundle.enc -pass pass:Deploy2023_4921

cd /home/user
rm -rf /home/user/deploy_source /home/user/deploy_bundle.tar.gz

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
