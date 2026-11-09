#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import csv
import random
import string
import os

random.seed(42)

categories = ['Electronics', 'Books', 'Clothing', 'Home', 'Toys']
filename = '/home/user/raw_reviews.csv'

def generate_id():
    return ''.join(random.choices(string.ascii_uppercase + string.digits, k=8))

data = []
# Header
data.append(['ID', 'Category', 'Rating', 'Date', 'Review'])

for i in range(5000):
    row_id = generate_id()
    cat = random.choice(categories)

    # Generate rating (10% chance of corruption)
    if random.random() < 0.10:
        rating = random.choice(['A', '0', '6', '', '3.5'])
    else:
        rating = str(random.randint(1, 5))

    # Generate date (5% chance of corruption)
    if random.random() < 0.05:
        date = f"2023/10/{random.randint(1,28):02d}" # invalid format
    else:
        month = random.randint(1, 12)
        day = random.randint(1, 28)
        date = f"2023-{month:02d}-{day:02d}"

    # Generate review (5% chance of empty/whitespace)
    if random.random() < 0.05:
        review = random.choice(['', '   ', '\t'])
    else:
        review = "Great product!" if (rating.isdigit() and int(rating) >= 4) else "It was okay."

    # ID corruption (2% chance)
    if random.random() < 0.02:
        row_id = "INVALID"

    data.append([row_id, cat, rating, date, review])

with open(filename, 'w', encoding='utf-16le', newline='') as f:
    writer = csv.writer(f)
    writer.writerows(data)

os.chmod(filename, 0o644)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
