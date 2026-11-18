#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip diffutils gawk coreutils
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/configs

printf "server=192.168.1.1\nport=8080\nmode=active\n" | iconv -f UTF-8 -t WINDOWS-1252 > /home/user/configs/v1.conf
printf "server=192.168.1.1\nport=8081\nmode=active\n" | iconv -f UTF-8 -t UTF-16LE > /home/user/configs/v2.conf
printf "server=192.168.1.1\nport=8081\nmode=passive\ntimeout=30\n" > /home/user/configs/v3.conf
printf "port=80\nmode=passive\ntimeout=30\n" | iconv -f UTF-8 -t ISO-8859-1 > /home/user/configs/v4.conf

cat << 'EOF' > /home/user/inventory.csv
version,file_path,encoding
1,/home/user/configs/v1.conf,WINDOWS-1252
2,/home/user/configs/v2.conf,UTF-16LE
3,/home/user/configs/v3.conf,UTF-8
4,/home/user/configs/v4.conf,ISO-8859-1
EOF

chmod -R 777 /home/user
