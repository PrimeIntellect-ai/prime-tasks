#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip openssh-client openssl bubblewrap
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/artifacts/ssh_keys
mkdir -p /home/user/artifacts/certs

# 1. Create SSH keys
ssh-keygen -t rsa -b 2048 -N "strongpassword123" -f /home/user/artifacts/ssh_keys/key1
ssh-keygen -t ed25519 -N "" -f /home/user/artifacts/ssh_keys/key2
ssh-keygen -t ecdsa -b 256 -N "anotherpassword!" -f /home/user/artifacts/ssh_keys/key3

# 2. Create Certificate Chain
cd /home/user/artifacts/certs
# Root CA
openssl req -x509 -newkey rsa:2048 -days 365 -nodes -keyout root.key -out root.pem -subj "/CN=Test Root CA"
# Intermediate CA
openssl req -newkey rsa:2048 -nodes -keyout intermediate.key -out intermediate.csr -subj "/CN=Test Intermediate CA"
openssl x509 -req -in intermediate.csr -CA root.pem -CAkey root.key -CAcreateserial -out intermediate.pem -days 365
# Leaf
openssl req -newkey rsa:2048 -nodes -keyout leaf.key -out leaf.csr -subj "/CN=test.local"
openssl x509 -req -in leaf.csr -CA intermediate.pem -CAkey intermediate.key -CAcreateserial -out leaf.pem -days 365

cd /home/user

chmod -R 777 /home/user
