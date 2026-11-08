#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip curl
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/words.txt
supernova
starburst
database
admin123
password
server
network
EOF

echo "22c83669bd7ff404a3f25c7ccddddc7f1e7371c1f7b02db703f8f17ebffdbf8b" > /home/user/hash.txt

chmod -R 777 /home/user
