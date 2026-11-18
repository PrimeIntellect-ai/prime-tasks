#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/data/reviews

    cat << 'EOF' > /tmp/setup_data.py
import csv
import os

data_dir = "/home/user/data/reviews"

files_data = [
    {
        "filename": "us_reviews.csv",
        "encoding": "utf-8",
        "rows": [
            ["id", "review_text"],
            ["1", "I really love the AB-12345, it works great!"],
            ["2", "The XYZ-98765 broke after two days. Do not buy XYZ-98765."],
            ["3", "No product mentioned here."]
        ]
    },
    {
        "filename": "eu_reviews.csv",
        "encoding": "latin-1",
        "rows": [
            ["id", "review_text"],
            ["4", "Das AB-12345 ist fantastisch. Äußerst empfehlenswert!"],
            ["5", "Mein ZZ-0000 ist kaputt..."]
        ]
    },
    {
        "filename": "jp_reviews.csv",
        "encoding": "shift_jis",
        "rows": [
            ["id", "review_text"],
            ["6", "このXYZ-98765は素晴らしいです。"],
            ["7", "AB-12345を買いました。"]
        ]
    },
    {
        "filename": "ru_reviews.csv",
        "encoding": "windows-1251",
        "rows": [
            ["id", "review_text"],
            ["8", "Отличный товар RU-55555, спасибо!"],
            ["9", "Я не рекомендую AB-12345."]
        ]
    }
]

for fd in files_data:
    filepath = os.path.join(data_dir, fd["filename"])
    with open(filepath, "w", encoding=fd["encoding"], newline='') as f:
        writer = csv.writer(f)
        writer.writerows(fd["rows"])

EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
