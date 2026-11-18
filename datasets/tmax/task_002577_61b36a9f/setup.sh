#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip git make gcc libssl-dev docker.io docker-compose-v2 openssh-server sudo
pip3 install pytest

useradd -m -s /bin/bash user || true

# Setup SSH for user
mkdir -p /run/sshd
mkdir -p /home/user/.ssh
ssh-keygen -t rsa -b 2048 -N "" -f /home/user/.ssh/id_rsa
cat /home/user/.ssh/id_rsa.pub > /home/user/.ssh/authorized_keys
chmod 700 /home/user/.ssh
chmod 600 /home/user/.ssh/*
chown -R user:user /home/user/.ssh

# Setup wrk
mkdir -p /app
git clone https://github.com/wg/wrk.git /app/wrk
cd /app/wrk
git checkout 4.2.0
sed -i 's/-lm //g' Makefile

# Setup deploy directory
mkdir -p /home/user/deploy

cat << 'EOF' > /home/user/deploy/docker-compose.yml
version: '3'
services:
  api:
    image: python:3.9-alpine
    command: sh -c "mkdir -p /web && echo 'OK' > /web/index.html && cd /web && python -m http.server 8000"
    networks:
      - back-tier
  nginx:
    image: nginx:alpine
    ports:
      - "9090:80"
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf
    networks:
      - front-tier
networks:
  front-tier:
  back-tier:
EOF

cat << 'EOF' > /home/user/deploy/nginx.conf
server {
    listen 80;
    location / {
        proxy_pass http://api:8000;
    }
}
EOF

chmod -R 777 /home/user
