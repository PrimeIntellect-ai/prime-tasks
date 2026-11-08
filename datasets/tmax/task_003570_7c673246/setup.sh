#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc openssl
pip3 install pytest cryptography

mkdir -p /home/user/certs
mkdir -p /home/user/tokens

# 1. Create the ELF binary
cat << 'EOF' > /home/user/legacy_auth.c
#include <stdio.h>
const char* ISSUER_ID = "ISSUER_ID=SEC_8832_XYZ";
int main() {
    printf("Auth module loaded.\n");
    return 0;
}
EOF
gcc /home/user/legacy_auth.c -o /home/user/legacy_auth_bin
rm -f /home/user/legacy_auth.c

# 2. Create Certificate Chain (Valid)
cd /home/user/certs
# CA
openssl req -new -x509 -days 365 -nodes -out ca.pem -keyout ca.key -subj "/C=US/O=DevSecOps/CN=RootCA"
# Intermediate
openssl req -new -nodes -out intermediate.csr -keyout intermediate.key -subj "/C=US/O=DevSecOps/CN=Intermediate"
cat << 'EOF' > extfile.cnf
basicConstraints=CA:TRUE
EOF
openssl x509 -req -in intermediate.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out intermediate.pem -days 365 -extfile extfile.cnf
# Leaf
openssl req -new -nodes -out leaf.csr -keyout leaf.key -subj "/C=US/O=DevSecOps/CN=LeafAuth"
openssl x509 -req -in leaf.csr -CA intermediate.pem -CAkey intermediate.key -CAcreateserial -out leaf.pem -days 365
rm -f *.key *.csr *.srl extfile.cnf
cd /home/user

# 3. Create JWT Tokens
echo -n "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyIjoiYWRtaW4ifQ.valid_sig_here" > /home/user/tokens/token1.jwt
echo -n "eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJ1c2VyIjoiYWRtaW4ifQ." > /home/user/tokens/token2.jwt
echo -n "eyJhbGciOiJOT05FIiwidHlwIjoiSldUIn0.eyJ1c2VyIjoiZ3Vlc3QifQ." > /home/user/tokens/token3.jwt

useradd -m -s /bin/bash user || true
chown -R user:user /home/user/certs /home/user/tokens /home/user/legacy_auth_bin
chmod -R 777 /home/user
