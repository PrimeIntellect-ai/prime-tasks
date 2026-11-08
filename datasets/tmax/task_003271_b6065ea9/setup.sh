#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pandas numpy scikit-learn

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/create_data.py
import csv
import os

os.makedirs('/home/user', exist_ok=True)

data = [
    (1, "Buy cheap viagra now!!!", 1),
    (2, "Hello friend, how are you doing today?", 0),
    (3, "CHEAP shoes for sale! Buy now", 1),
    (4, "Meeting at 5pm tomorrow.", 0),
    (5, "Win a free iPhone, click here to win", 1),
    (6, "Can we reschedule our meeting?", 0),
    (7, "Free money!!! Cheap fast loans", 1),
    (8, "Lunch was great, let's do it again.", 0),
    (9, "Viagra and cialis, fast shipping.", 1),
    (10, "Please review the attached document.", 0),
    (11, "You are a winner! Free vacation!", 1),
    (12, "Don't forget to buy milk.", 0),
    (13, "Click here for cheap medications", 1),
    (14, "I will be late to the meeting.", 0),
    (15, "Limited time offer, buy one get one free", 1),
    (16, "Happy birthday! Hope you have a great day.", 0),
    (17, "Earn money fast from home!!!", 1),
    (18, "See you at the conference.", 0),
    (19, "Free trial for exclusive members.", 1),
    (20, "What time is the game?", 0)
]

with open('/home/user/emails.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['id', 'text', 'spam'])
    for row in data:
        writer.writerow(row)
EOF

python3 /tmp/create_data.py
rm /tmp/create_data.py

chmod -R 777 /home/user
