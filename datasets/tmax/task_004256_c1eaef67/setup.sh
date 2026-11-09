#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest Levenshtein

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import csv

data = [
    ("Alice Smith", " alice@example.com ", "123 Main St."),
    ("Alice Smith", "ALICE@example.com", "123 Main St"),
    ("Bob Jones", "bob1@test.com", "456 Oak Avenue!"),
    ("Bob Jomes", "bob2@test.com", "456 Oak Avenue?"),
    ("Bobb Jomes", "bob3@test.com", "456OakAvenue"),
    ("Charlie", "char@lie.com", "789 Pine"),
    ("Charlee", "char@lie.com", "789 Pine Rd"),
    ("Charlee", "ch@rlie.com", "789 Pine"),
    ("Ren\u00e9", "rene1@test.com", "Paris 101"),
    ("Rene\u0301", "rene2@test.com", "Paris 101"),
    ("David", "dave@example.com", "101 Elm")
]

with open('/home/user/input.csv', 'w', newline='', encoding='utf-8') as f:
    writer = csv.writer(f)
    writer.writerow(["name", "email", "address"])
    for row in data:
        writer.writerow(row)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
