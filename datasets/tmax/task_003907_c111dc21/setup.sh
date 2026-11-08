#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tzdata jq tar curl
    pip3 install pytest

    mkdir -p /home/user/backup

    cat << 'EOF' > /home/user/backup/deploy_pipeline.log
[2023-10-01 14:22:10 UTC] DEPLOY_ID: 101 STATUS: FAILED
[2023-10-02 09:15:00 UTC] DEPLOY_ID: 102 STATUS: SUCCESS
[2023-10-03 11:45:30 UTC] DEPLOY_ID: 103 STATUS: FAILED
[2023-10-04 16:30:00 UTC] DEPLOY_ID: 104 STATUS: SUCCESS
[2023-10-05 08:10:00 UTC] DEPLOY_ID: 105 STATUS: IN_PROGRESS
EOF

    cat << 'EOF' > /home/user/backup/proxy_template.conf
server {
    listen 80;
    server_name example.com;
    location / {
        proxy_pass http://backend_cluster;
    }
}
server {
    listen 443;
    server_name secure.example.com;
    ssl_certificate /etc/ssl/certs/cert.pem;
    location /api {
        proxy_pass http://api_cluster;
    }
}
EOF

    cd /home/user/backup
    tar -czf /home/user/backup.tar.gz deploy_pipeline.log proxy_template.conf
    cd /home/user
    rm -rf /home/user/backup

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
