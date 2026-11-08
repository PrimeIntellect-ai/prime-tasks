#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make libcurl4-openssl-dev docker.io docker-compose
pip3 install pytest

mkdir -p /home/user/services/flask_app
mkdir -p /home/user/services/nginx/html

cat << 'EOF' > /home/user/services/docker-compose.yml
version: '3'
services:
  nginx:
    image: nginx:latest
    ports:
      - "8081:80"
  flask:
    build: ./flask_app
    ports:
      - "5001:5000"
  redis:
    image: redis:latest
    ports:
      - "6380:6379"
EOF

cat << 'EOF' > /home/user/services/flask_app/.env
REDIS_URL=redis://localhost:6380
UPSTREAM_URL=http://localhost:8081
EOF

cat << 'EOF' > /home/user/indexer.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    // TODO: Implement indexer
    return 0;
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
