#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip openssl
pip3 install pytest cryptography paramiko

useradd -m -s /bin/bash user || true
mkdir -p /home/user/audit_materials

# Generate an RSA key with a 4-digit passphrase (6194) using openssl to bypass ssh-keygen length limits
openssl genrsa -aes128 -passout pass:6194 -out /home/user/audit_materials/legacy_key.pem 2048

# Create the HTTP traffic log
cat << 'EOF' > /home/user/audit_materials/http_traffic.log
HTTP/1.1 200 OK
Date: Wed, 21 Oct 2023 07:28:00 GMT
Server: Apache/2.4.41 (Ubuntu)
Set-Cookie: JSESSIONID=node0123456789; Path=/
Set-Cookie: AuditSession=sec_token_88ab49f2b3; Secure; HttpOnly; SameSite=Strict
Connection: close
Content-Type: text/html; charset=UTF-8
EOF

chown -R user:user /home/user/audit_materials
chmod -R 777 /home/user
