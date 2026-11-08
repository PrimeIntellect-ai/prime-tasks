#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest

    mkdir -p /home/user/audit_data

    cat << 'EOF' > /home/user/audit_data/nginx.conf
server {
    listen 443 ssl;
    server_name secure.internal.com;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; object-src 'none';";
}
EOF

    cat << 'EOF' > /home/user/audit_data/auth.js
function generateSessionToken() {
    // Generate a quick token for the user session
    return Math.random().toString(36).substring(2, 15) + Math.random().toString(36).substring(2, 15);
}
module.exports = { generateSessionToken };
EOF

    openssl req -x509 -newkey rsa:2048 -keyout /tmp/key.pem -out /home/user/audit_data/cert.pem -days 365 -nodes -subj "/C=US/ST=California/L=San Francisco/O=Security Corp/CN=secure.internal.com"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
