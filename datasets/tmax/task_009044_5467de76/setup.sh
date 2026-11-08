#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc openssl gawk
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/audit_data/requests
mkdir -p /home/user/audit_data/uploads
mkdir -p /home/user/audit_data/certs

cd /home/user/audit_data/certs
openssl req -x509 -newkey rsa:2048 -keyout ca.key -out ca.pem -days 365 -nodes -subj "/CN=AuditCA"
openssl req -newkey rsa:2048 -keyout req1.key -out req1.csr -nodes -subj "/CN=User1"
openssl x509 -req -in req1.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out req1.pem -days 365
openssl req -x509 -newkey rsa:2048 -keyout req2.key -out req2.pem -days 365 -nodes -subj "/CN=User2"
openssl req -newkey rsa:2048 -keyout req3.key -out req3.csr -nodes -subj "/CN=User3"
openssl x509 -req -in req3.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out req3.pem -days 365

cd /home/user/audit_data/requests

cat << 'EOF' > req1.txt
POST /upload HTTP/1.1
Host: example.com
Cookie: session_id=abc123xyz
Content-Type: multipart/form-data; boundary=----WebKitFormBoundary7MA4YWxkTrZu0gW

------WebKitFormBoundary7MA4YWxkTrZu0gW
Content-Disposition: form-data; name="file"; filename="report.pdf"
Content-Type: application/pdf

EOF
echo "%PDF-1.4..." >> req1.txt
cat << 'EOF' >> req1.txt
------WebKitFormBoundary7MA4YWxkTrZu0gW--
EOF

cat << 'EOF' > req2.txt
POST /upload HTTP/1.1
Host: example.com
Cookie: session_id=malicious999
Content-Type: multipart/form-data; boundary=----WebKitFormBoundary7MA4YWxkTrZu0gW

------WebKitFormBoundary7MA4YWxkTrZu0gW
Content-Disposition: form-data; name="file"; filename="../../../etc/passwd"
Content-Type: text/plain

root:x:0:0:root:/root:/bin/bash
------WebKitFormBoundary7MA4YWxkTrZu0gW--
EOF

cat << 'EOF' > req3.txt
POST /upload HTTP/1.1
Host: example.com
Cookie: session_id=legit888
Content-Type: multipart/form-data; boundary=----WebKitFormBoundary7MA4YWxkTrZu0gW

------WebKitFormBoundary7MA4YWxkTrZu0gW
Content-Disposition: form-data; name="file"; filename="image.png"
Content-Type: image/png

\x89PNG\r\n\x1a\n...
------WebKitFormBoundary7MA4YWxkTrZu0gW--
EOF

cd /home/user/audit_data
echo "report content" > uploads/report.pdf
echo "root user data" > uploads/passwd
echo "image data" > uploads/image.png

sha256sum uploads/report.pdf | awk '{print $1 "  report.pdf"}' > manifest.txt
sha256sum uploads/passwd | awk '{print $1 "  passwd"}' >> manifest.txt
echo "0000000000000000000000000000000000000000000000000000000000000000  image.png" >> manifest.txt

chown -R user:user /home/user/audit_data
chmod -R 777 /home/user
