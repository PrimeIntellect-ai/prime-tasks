#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user/configs

cat << 'EOF' > /home/user/configs/config_20231001_0800.txt
server=local; port=8080; # configuration initiale
EOF

cat << 'EOF' > /home/user/configs/config_20231001_1800.txt
server=local; port=8080; # configuration initiale 変更
EOF

cat << 'EOF' > /home/user/configs/config_20231002_0900.txt
server=prod; port=80; # configuration en production 変更
EOF

cat << 'EOF' > /home/user/configs/config_20231003_1000.txt
server=prod; port=443; tls=true; # configuration en production 変更
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
