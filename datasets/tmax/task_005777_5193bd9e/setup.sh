#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip git golang-go
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/deploy.git
git init --bare /home/user/deploy.git

echo '{"db_password": "supersecret"}' > /home/user/app_config.json

chown -R user:user /home/user
chmod -R 777 /home/user
chmod 644 /home/user/app_config.json
