#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip openssh-client
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/jwt_logs.txt
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c
eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJzdWIiOiJhZG1pbiIsImlhdCI6MTYxNjIzOTAyMn0.
eyJhbGciOiJOb25lIiwidHlwIjoiSldUIn0.eyJzdWIiOiJyb290IiwiaWF0IjoxNjE2MjM5MDIyfQ.
eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyMSIsImlhdCI6MTYxNjIzOTAyMn0.dummy_signature_bytes
EOF

chmod -R 777 /home/user
