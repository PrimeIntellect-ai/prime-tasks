#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_data.py
import csv

data = [
    ("msg_01", "UTF-8", "Hello, World!"),
    ("msg_02", "LATIN1", "Caf\xe9 au lait."),
    ("msg_03", "UTF-8", "This is a slightly longer message to test the medium stratum classification!"),
    ("msg_04", "UTF-8", "Short text."),
    ("msg_05", "UTF-8", "Another medium string with exactly eight words in it."),
    ("msg_06", "UTF-8", "A B C D E F G H I J K L M N O P Q"),
    ("msg_07", "UTF-8", "One two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen"),
    ("msg_08", "LATIN1", "El ni\xf1o corre r\xe1pido por el bosque verde."),
]

with open("/home/user/raw_chat.tsv", "w", newline="", encoding="latin1") as f:
    writer = csv.writer(f, delimiter='\t', quoting=csv.QUOTE_NONE, escapechar='\\')
    for row in data:
        f.write(f"{row[0]}\t{row[1]}\t{row[2]}\n")
EOF
    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    chmod -R 777 /home/user
