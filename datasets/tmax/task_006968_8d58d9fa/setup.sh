#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/inputs
    mkdir -p /home/user/outputs

    python3 -c "
import csv

data = [
    ['timestamp', 'ip_address', 'email'],
    ['1700000000', '192.168.1.50', 'alice@example.com'],
    ['1700000010', '192.168.1.51', 'bob@test.org'],
    ['1700000030', '192.168.1.50', 'alice.work@example.com'],
    ['1700000050', '10.0.0.5', 'charlie@foo.net'],
    ['1700000070', '192.168.1.52', 'dave@bar.com'],
    ['1700000100', '192.168.1.100', 'eve@baz.com']
]

with open('/home/user/inputs/auth_logs.csv', 'w', encoding='cp1252', newline='') as f:
    writer = csv.writer(f)
    writer.writerows(data)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
