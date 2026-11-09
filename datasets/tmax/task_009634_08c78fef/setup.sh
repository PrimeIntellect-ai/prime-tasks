#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_data.py
import csv

data = [
    ["doc_id", "text", "author", "views"],
    ["1", "This is a completely normal sentence with enough words to pass.", "Alice", "150"],
    ["2", "", "Bob", "200"],
    ["3", "   ", "Charlie", "300"],
    ["4", "Another valid sentence for the dataset right here.", "", "450"],
    ["5", "A valid sentence, but views are missing here.", "Eve", ""],
    ["6", "Wow, this post went viral and has way too many views!", "Frank", "105000"],
    ["7", "Too short.", "Grace", "50"],
    ["8", "This one is exceptionally long and just keeps going and going and going and going to make sure that it absolutely exceeds the fifty token limit that was established in the rules of this data engineering task so it should definitely be removed from the final output JSON lines file because it is an outlier.", "Heidi", "100"],
    ["9", "Special characters! @ # $ % should be removed 123.", "Ivan", "75"]
]

with open('/home/user/raw_data.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerows(data)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
