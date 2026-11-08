#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip openssl
pip3 install pytest

mkdir -p /home/user/release_bundle

# 1. Create requirements.txt
cat << 'EOF' > /home/user/release_bundle/requirements.txt
Flask==2.2.3
requests==2.29.0
Werkzeug==2.2.3
EOF

# 2. Create traffic.log
cat << 'EOF' > /home/user/release_bundle/traffic.log
192.168.1.10 - - [10/Oct/2023:13:55:36 -0700] "GET / HTTP/1.1" 200 2326
192.168.1.11 - - [10/Oct/2023:13:55:40 -0700] "POST /login HTTP/1.1" 200 512
192.168.1.12 - - [10/Oct/2023:13:56:01 -0700] "GET /search?q=admin' OR '1'='1 HTTP/1.1" 403 124
192.168.1.10 - - [10/Oct/2023:13:56:05 -0700] "GET /styles.css HTTP/1.1" 200 1024
EOF

# 3. Create Certificates (Valid chain)
cd /home/user/release_bundle
# Create CA
openssl req -x509 -sha256 -days 365 -nodes -newkey rsa:2048 -subj "/CN=Test CA" -keyout ca.key -out ca.crt
# Create Server CSR and Key
openssl req -new -newkey rsa:2048 -nodes -subj "/CN=localhost" -keyout server.key -out server.csr
# Sign Server Cert with CA
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt -days 365 -sha256

# Create user and fix permissions
useradd -m -s /bin/bash user || true
chown -R user:user /home/user/release_bundle
chmod -R 777 /home/user
