#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest chardet pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import csv

os.makedirs('/home/user/reviews', exist_ok=True)

data_files = [
    {
        "filename": "data_1.csv",
        "encoding": "utf-8",
        "rows": [
            ("2023-10-01", "user1", "Good app!"),
            ("2023-10-01", "user2", "Nice\u2000work"),
            ("2023-10-02", "user3", "I like it"),
            ("2023-10-02", "user4", "Awesome!!"),
        ]
    },
    {
        "filename": "data_2.csv",
        "encoding": "iso-8859-1",
        "rows": [
            ("2023-10-03", "user5", "Tres bien"),
            ("2023-10-03", "user6", "Excelente"),
            ("2023-10-04", "user7", "This is a very very long review"),
            ("2023-10-04", "user8", "Another extremely long comment"),
        ]
    },
    {
        "filename": "data_3.csv",
        "encoding": "shift_jis",
        "rows": [
            ("2023-10-05", "user9", "\u3059\u3070\u3089\u3057\u3044"),
            ("2023-10-05", "user10", "\u3088\u3044\u3067\u3059\u306d"),
            ("2023-10-06", "user11", "Perfect!!"),
            ("2023-10-06", "user12", "Very good"),
        ]
    },
    {
        "filename": "data_4.csv",
        "encoding": "utf-16",
        "rows": [
            ("2023-10-07", "user13", "Not bad!!"),
            ("2023-10-07", "user14", "Five star"),
            ("2023-10-08", "user15", "Here is a massive review text jump"),
            ("2023-10-08", "user16", "Wow the length is huge today!!"),
        ]
    },
    {
        "filename": "data_5.csv",
        "encoding": "cp1251",
        "rows": [
            ("2023-10-09", "user17", "\u0425\u043e\u0440\u043e\u0448\u043e"),
            ("2023-10-09", "user18", "\u041e\u0442\u043b\u0438\u0447\u043d\u043e"),
        ]
    }
]

for f in data_files:
    filepath = os.path.join('/home/user/reviews', f["filename"])
    with open(filepath, 'w', encoding=f["encoding"], newline='') as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow(["Date", "Username", "Review_Text"])
        for row in f["rows"]:
            writer.writerow(row)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
