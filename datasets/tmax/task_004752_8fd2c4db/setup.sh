#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas chardet

    mkdir -p /home/user/customer_feedback

    cat << 'EOF' > /tmp/setup_data.py
import csv

data_utf8 = [
    ["id", "name", "email", "phone", "rating", "comments"],
    ["101", "Alice Smith", "alice.smith@test.com", "123-456-7890", "5", "Great service!"],
    ["102", "Bob Jones", "bob_jones_no_domain", "555-9999", "4", "Okay"],
    ["103", "Charlie", "charlie@domain.com", "987654321", "6", "Too high rating"]
]

data_iso = [
    ["id", "name", "email", "phone", "rating", "comments"],
    ["201", "José García", "jose@empresa.es", "+34 600 123 456", "4", "Buen trabajo"],
    ["abc", "Bad ID", "bad@id.com", "1111", "3", "ID is letters"]
]

data_utf16 = [
    ["id", "name", "email", "phone", "rating", "comments"],
    ["301", "Björn", "bjorn@sverige.se", "08-123 45 67", "1", "Terrible!"],
    ["302", "Müller", "muller@deutschland.de", "123", "5", "Sehr gut"],
    ["303", "Empty Phone", "empty@phone.com", "", "2", "No phone provided"]
]

def write_csv(filename, data, encoding):
    with open(filename, 'w', encoding=encoding, newline='') as f:
        writer = csv.writer(f)
        writer.writerows(data)

write_csv('/home/user/customer_feedback/file1.csv', data_utf8, 'utf-8')
write_csv('/home/user/customer_feedback/file2.csv', data_iso, 'iso-8859-1')
write_csv('/home/user/customer_feedback/file3.csv', data_utf16, 'utf-16')
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
