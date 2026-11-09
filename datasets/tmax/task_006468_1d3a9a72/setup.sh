#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip openssl
pip3 install pytest

mkdir -p /home/user/audit_target
cd /home/user/audit_target

# 1. Create wordlist
cat << 'EOF' > wordlist.txt
admin123
password
qwerty
secret2023
deploy_prod
root
EOF

# 2. Create deploy.py
cat << 'EOF' > deploy.py
# Deployment Configuration
ENCODED_HASH = "cnRzI3Nyc2BxI2JxcnN1eXNyfHFidHM="
XOR_KEY = 0x42
# TODO: Implement deployment logic
EOF

# 3. Create Certificates
# Generate CA
openssl req -x509 -newkey rsa:2048 -days 365 -nodes -keyout ca.key -out ca.crt -subj "/CN=Audit CA"

# Generate Server Key (Encrypted with secret2023)
openssl genrsa -aes256 -passout pass:secret2023 -out server.key 2048

# Generate Server CSR with specific OU
openssl req -new -key server.key -passin pass:secret2023 -out server.csr -subj "/C=US/O=Audit Target/OU=PermCheck-Fail-RootAccess/CN=server.local"

# Sign Server Cert with CA
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt -days 365

# Cleanup unnecessary files
rm -f ca.key server.csr ca.srl

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
