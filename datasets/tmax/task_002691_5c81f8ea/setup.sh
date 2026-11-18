#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tar gzip coreutils file
pip3 install pytest

mkdir -p /home/user/backups
cd /home/user/backups

# Create original logs with UTF-16LE encoding
printf "ID: Alpha77\nSystem status: normal\n" | iconv -f UTF-8 -t UTF-16LE > log_01.txt
printf "ID: Bravo88\nSystem status: warning\n" | iconv -f UTF-8 -t UTF-16LE > log_02.txt
printf "ID: Charlie99\nSystem status: critical\n" | iconv -f UTF-8 -t UTF-16LE > log_03.txt

# Tar and gzip them
tar -czf backup_01.tar.gz log_01.txt
tar -czf backup_02.tar.gz log_02.txt
tar -czf backup_03.tar.gz log_03.txt

# Replace first 4 bytes with 'BKP1'
for i in 1 2 3; do
    printf "BKP1" | dd of=backup_0${i}.tar.gz bs=1 count=4 conv=notrunc
    mv backup_0${i}.tar.gz backup_0${i}.dat
done

rm -f log_*.txt

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
