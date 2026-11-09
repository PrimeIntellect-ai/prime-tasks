#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip coreutils findutils gawk grep libc-bin
pip3 install pytest

mkdir -p /home/user/legacy_data/docs
mkdir -p /home/user/legacy_data/logs/old

# Create backup.conf
cat << 'EOF' > /home/user/backup.conf
txt,ISO-8859-1
log,UTF-16LE
dat,WINDOWS-1252
EOF

# Create files with specific encodings
echo "Café et croissant" | iconv -f UTF-8 -t ISO-8859-1 > /home/user/legacy_data/docs/menu.txt
echo "Über den Wolken" | iconv -f UTF-8 -t ISO-8859-1 > /home/user/legacy_data/docs/sky.txt

echo "System error: Äquator" | iconv -f UTF-8 -t UTF-16LE > /home/user/legacy_data/logs/old/sys.log
echo "Booting..." | iconv -f UTF-8 -t UTF-16LE > /home/user/legacy_data/logs/boot.log

echo "Data: £100" | iconv -f UTF-8 -t WINDOWS-1252 > /home/user/legacy_data/financial.dat

# Ignored file
echo "Ignore me" > /home/user/legacy_data/ignore.csv

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
