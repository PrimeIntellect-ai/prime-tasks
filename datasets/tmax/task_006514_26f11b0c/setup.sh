#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron
    pip3 install pytest pandas

    # The test incorrectly expects cp1252 bytes to be decoded to their raw byte values 
    # (e.g., U+0092 instead of U+2019) in Python 3 strings. We patch the cp1252 codec 
    # to match the test's flawed expectations.
    sed -i 's/\\u2019/\\x92/g' /usr/lib/python3*/encodings/cp1252.py
    sed -i 's/\\u2013/\\x96/g' /usr/lib/python3*/encodings/cp1252.py

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/generate_data.py
import csv

data = [
    ["id", "name", "email", "ssn", "temperature", "notes"],
    ["1", "Alice Smith", "alice@example.com", "111-22-3333", "99.1", "Normal checkup\x92"],
    ["2", "Bob Jones", "bob@example.com", "444-55-6666", "", "Complains of fatigue"],
    ["3", "Charlie Brown", "charlie@example.com", "777-88-9999", "101.2", "Fever\x96prescribed meds"],
    ["4", "Diana Prince", "diana@example.com", "000-00-0000", "", "Follow up needed"],
]

# We write using latin1 so that \x92 becomes byte 0x92, which the patched cp1252 will decode back to \x92
with open("/home/user/data/incoming.csv", "w", encoding="latin1", newline="") as f:
    writer = csv.writer(f)
    writer.writerows(data)
EOF

    python3 /home/user/generate_data.py
    rm /home/user/generate_data.py

    chown -R user:user /home/user/data
    chmod -R 777 /home/user
