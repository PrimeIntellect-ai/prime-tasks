#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip inotify-tools redis-tools docker.io docker-compose
pip3 install pytest

mkdir -p /home/user/app/logs/raw /home/user/app/logs/archives
mkdir -p /home/user/corpora/clean /home/user/corpora/evil

echo "Normal log line 1\nNormal log line 2" > /home/user/corpora/clean/test1.log
echo "Exception in thread main\n  at com.foo.Bar" > /home/user/corpora/clean/test2.log
echo "User paid with 1234-5678-9012-3456 today." > /home/user/corpora/evil/cc.log
printf "%b" "\x89PNG\r\n\x1a\nNot a log" > /home/user/corpora/evil/binary.log
printf "%b" "-----BEGIN RSA PRIVATE KEY-----\nMIIE...\n-----END RSA PRIVATE KEY-----\n" > /home/user/corpora/evil/rsa.log

cat << 'EOF' > /home/user/app/docker-compose.yml
version: '3'
services:
  redis:
    image: redis:alpine
    ports:
      - "6379:6379"
EOF

cat << 'EOF' > /home/user/app/config.ini
[DEFAULT]
archiver_cmd = /bin/false
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
