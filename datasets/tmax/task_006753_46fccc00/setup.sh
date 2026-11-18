#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip zip bzip2 tar
pip3 install pytest

mkdir -p /home/user/staging
mkdir -p /home/user/curated

# Create Archive 1 (alice, zip)
mkdir -p /tmp/arch1/bin
echo "echo hello" > /tmp/arch1/bin/execute
echo '{"author": "alice", "build": 101}' > /tmp/arch1/meta.json
cd /tmp/arch1 && zip -r /home/user/staging/app_v1.zip .

# Create Archive 2 (bob, tar.gz)
mkdir -p /tmp/arch2/lib
echo "binarydata" > /tmp/arch2/lib/libfoo.so
echo '{"author": "bob", "build": 102}' > /tmp/arch2/meta.json
cd /tmp/arch2 && tar -czf /home/user/staging/lib_v2.tar.gz .

# Create Archive 3 (alice, tar.bz2)
mkdir -p /tmp/arch3/src
echo "print('hello')" > /tmp/arch3/src/tool.py
echo '{"author": "alice", "build": 103}' > /tmp/arch3/meta.json
cd /tmp/arch3 && tar -cjf /home/user/staging/tool_v3.tar.bz2 .

# Create Archive 4 (charlie, zip)
mkdir -p /tmp/arch4/bin
echo "echo bye" > /tmp/arch4/bin/execute2
echo '{"author": "charlie", "build": 104}' > /tmp/arch4/meta.json
cd /tmp/arch4 && zip -r /home/user/staging/app_v2.zip .

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
