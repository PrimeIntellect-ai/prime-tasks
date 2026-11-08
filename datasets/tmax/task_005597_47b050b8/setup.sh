#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc libssl-dev openssl xxd coreutils
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/incident
cd /home/user/incident

# 1. Generate Certificates
# Root CA
openssl req -x509 -newkey rsa:2048 -days 365 -nodes -keyout root.key -out root.pem -subj "/CN=TrustedRootCA"
# Intermediate CA
openssl req -newkey rsa:2048 -nodes -keyout int.key -out int.csr -subj "/CN=IntermediateCA"
openssl x509 -req -in int.csr -CA root.pem -CAkey root.key -CAcreateserial -out int.pem -days 365
# Leaf Cert
openssl req -newkey rsa:2048 -nodes -keyout leaf.key -out leaf.csr -subj "/CN=malicious-c2.local"
openssl x509 -req -in leaf.csr -CA int.pem -CAkey int.key -CAcreateserial -out leaf.pem -days 365
# Create Chain
cat leaf.pem int.pem > c2_chain.pem

# 2. Setup Crypto and Plaintext
KEY_HEX="0123456789abcdef0123456789abcdef"
IV_HEX="abcdef0123456789abcdef0123456789"
echo "KEY=$KEY_HEX" > crypto.txt
echo "IV=$IV_HEX" >> crypto.txt

PLAINTEXT='{"username":"sysadmin","session_id":"98765","ssn":"999-88-7777","role":"root"}'

# Encrypt the plaintext using AES-128-CBC
# Convert hex key/iv to binary for openssl enc
ENCRYPTED_HEX=$(echo -n "$PLAINTEXT" | openssl enc -aes-128-cbc -K $KEY_HEX -iv $IV_HEX | xxd -p -c 256 | tr -d '\n')

# 3. Create Traffic Log
cat <<EOF > traffic.log
POST /api/v1/update HTTP/1.1
Host: malicious-c2.local
User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64)
Cookie: session=$ENCRYPTED_HEX; other=value
Content-Length: 0
Connection: close

EOF

chmod -R 777 /home/user
