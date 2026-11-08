#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
pip3 install pytest

mkdir -p /home/user/data

cat << 'EOF' > /home/user/data/raw_logs_utf8.csv
1,500,100,défaut ERR-SYS-01 system down
2,200,50,OK all good
3,500,200,erreur ERR-DBX-99 timeout
4,502,300,fatal ERR-NET-42 connection lost
5,500,400,défaut ERR-SYS-02 disk full
6,502,500,critique ERR-NET-99 routing failed
7,502,600,erreur ERR-NET-01 packet drop
8,404,150,not found
9,500,700,ERR-APP-00 syntax error
EOF

iconv -f UTF-8 -t ISO-8859-1 /home/user/data/raw_logs_utf8.csv > /home/user/data/raw_logs.csv
rm /home/user/data/raw_logs_utf8.csv

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
