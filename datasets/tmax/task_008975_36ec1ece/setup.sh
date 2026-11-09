#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip zip tar gawk curl build-essential cargo
pip3 install pytest

mkdir -p /home/user/project_dump
mkdir -p /tmp/b1 /tmp/b2 /tmp/master

# ELF 1
printf "\x7f\x45\x4c\x46\x01\x01\x01\x00" > /tmp/b1/bin1.bin
dd if=/dev/urandom bs=1 count=100 >> /tmp/b1/bin1.bin 2>/dev/null

# WAL 1
printf "\x37\x7f\x06\x82\x00\x00\x00\x00" > /tmp/b1/db.data
dd if=/dev/urandom bs=1 count=100 >> /tmp/b1/db.data 2>/dev/null

# Dummy
echo "just text" > /tmp/b1/readme.txt

# ELF 2
printf "\x7f\x45\x4c\x46\x02\x01\x01\x00" > /tmp/b2/bin2.out
dd if=/dev/urandom bs=1 count=50 >> /tmp/b2/bin2.out 2>/dev/null

# Fake WAL (bad magic)
printf "\x37\x7f\x06\x84\x00\x00\x00\x00" > /tmp/b2/fake.wal

# Create archives
cd /tmp/b1 && tar -czf ../b1.tar.gz *
cd /tmp/b2 && zip ../b2.zip *

# Move to master
mv /tmp/b1.tar.gz /tmp/master/
mv /tmp/b2.zip /tmp/master/

# Create master
cd /tmp/master && zip /home/user/project_dump/master.zip *

# Store expected hashes
sha256sum /tmp/b1/bin1.bin | awk '{print $1}' > /tmp/hash_elf1
sha256sum /tmp/b2/bin2.out | awk '{print $1}' > /tmp/hash_elf2
sha256sum /tmp/b1/db.data | awk '{print $1}' > /tmp/hash_wal1

useradd -m -s /bin/bash user || true
chown -R user:user /home/user/project_dump
chmod -R 777 /home/user
