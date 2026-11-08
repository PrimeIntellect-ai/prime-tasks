#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user/raw_source/docs/manuals
mkdir -p /home/user/raw_source/docs/api

echo "Welcome to the AcmeCorp documentation." > /home/user/raw_source/docs/intro.txt
echo "AcmeCorp provides the best widgets." >> /home/user/raw_source/docs/intro.txt

python3 -c '
import os
with open("/home/user/raw_source/docs/manuals/finance.txt", "wb") as f:
    f.write("AcmeCorp financial report for the café.\n".encode("iso-8859-1"))
with open("/home/user/raw_source/docs/api/index.txt", "wb") as f:
    f.write("AcmeCorp API résumé.\n".encode("iso-8859-1"))
'

ln -s ../../docs /home/user/raw_source/docs/manuals/loop_back

cd /home/user/raw_source
tar -czf /home/user/legacy_docs.tar.gz docs/
cd /home/user
rm -rf /home/user/raw_source

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
