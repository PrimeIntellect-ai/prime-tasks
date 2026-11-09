#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
pip3 install pytest

mkdir -p /home/user/data

cat << 'EOF' > /home/user/data/gen.py
# -*- coding: utf-8 -*-
data = [
    ("1", "René", "Boss"),
    ("2", "Rene", "BossDuplicate"),
    ("3", "Françoise", "Dev"),
    ("4", "Francoise", "DevDup"),
    ("5", "Günter", "Admin"),
    ("6", "Gunter", "AdminDup"),
    ("7", "Günterx", "AdminDup2"),
    ("8", "Gunterxy", "AdminDup3"),
    ("9", "João", "User"),
    ("10", "Joao", "UserDup"),
    ("11", "Joã", "UserDup2")
]

with open("/home/user/data/input.csv", "wb") as f:
    for row in data:
        line = f"{row[0]},{row[1]},{row[2]}\n"
        f.write(line.encode("iso-8859-1"))
EOF

python3 /home/user/data/gen.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
