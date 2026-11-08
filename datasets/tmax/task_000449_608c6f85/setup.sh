#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/data

cat << 'EOF' > /tmp/setup.py
import os

os.makedirs('/home/user/data', exist_ok=True)

csv_content = """transaction_id,customer_name,email,amount,notes
T001,José Silva,jose.silva@example.com,150.00,Pago de café
T002,Maria García,maria.g@test.org,200.50,Reembolso
T001,José Silva,jose.silva@example.com,150.00,Pago de café
T003,René Descartes,rene@philosophy.fr,99.99,L'achat
T004,Jürgen Müller,jurgen.m@berlin.de,50.00,Groß
T002,Maria García,maria.g@test.org,200.50,Reembolso
T005,François Dubois,francois@paris.fr,12.50,Très bien
"""

with open('/home/user/data/raw_transactions.csv', 'w', encoding='iso-8859-1') as f:
    f.write(csv_content)
EOF

python3 /tmp/setup.py
rm /tmp/setup.py

chmod -R 777 /home/user
