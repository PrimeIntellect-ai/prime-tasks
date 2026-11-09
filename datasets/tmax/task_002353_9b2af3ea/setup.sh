#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the database setup script
    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import random
from datetime import datetime, timedelta

def setup_db():
    random.seed(42)
    conn = sqlite3.connect('/home/user/logistics.db')
    c = conn.cursor()

    c.execute('CREATE TABLE couriers (id INTEGER PRIMARY KEY, name TEXT)')
    c.execute('CREATE TABLE deliveries (id INTEGER PRIMARY KEY, courier_id INTEGER, delivery_time_mins INTEGER, created_at DATETIME)')
    c.execute('CREATE TABLE reviews (delivery_id INTEGER PRIMARY KEY, rating INTEGER)')

    # Generate Couriers
    for i in range(1, 51):
        c.execute('INSERT INTO couriers (id, name) VALUES (?, ?)', (i, f'Courier_{i}'))

    # Generate Deliveries
    delivery_id = 1
    start_date = datetime(2023, 1, 1)
    for courier_id in range(1, 51):
        num_deliveries = random.randint(10, 30)
        current_time = start_date + timedelta(days=random.randint(0, 10))
        for _ in range(num_deliveries):
            time_mins = random.randint(15, 120)
            c.execute('INSERT INTO deliveries (id, courier_id, delivery_time_mins, created_at) VALUES (?, ?, ?, ?)', 
                      (delivery_id, courier_id, time_mins, current_time.strftime('%Y-%m-%d %H:%M:%S')))

            # 70% chance of a review
            if random.random() < 0.7:
                rating = random.choices([1, 2, 3, 4, 5], weights=[5, 5, 10, 30, 50])[0]
                c.execute('INSERT INTO reviews (delivery_id, rating) VALUES (?, ?)', (delivery_id, rating))

            delivery_id += 1
            current_time += timedelta(hours=random.randint(1, 48))

    conn.commit()
    conn.close()

if __name__ == '__main__':
    setup_db()
EOF

    # Run the setup script to generate the database
    python3 /tmp/setup_db.py

    # Clean up
    rm /tmp/setup_db.py

    # Ensure permissions are correct
    chmod -R 777 /home/user
