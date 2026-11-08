#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data/events

    python3 -c "
import os
import sqlite3
import json

os.makedirs('/home/user/data/events', exist_ok=True)

# 1. Setup SQLite
conn = sqlite3.connect('/home/user/data/users.db')
c = conn.cursor()
c.execute('CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, country TEXT, age INTEGER, status TEXT)')

users_data = [
    (1, 'Alice', 'USA', 22, 'active'),
    (2, 'Bob', 'UK', 30, 'active'),
    (3, 'Charlie', 'USA', 40, 'active'),
    (4, 'Diana', 'Canada', 28, 'active'),
    (5, 'Eve', 'UK', 55, 'inactive'),
    (6, 'Frank', 'USA', 24, 'active'),
    (7, 'Grace', 'Canada', 33, 'active'),
    (8, 'Hank', 'UK', 31, 'active')
]
c.executemany('INSERT INTO users VALUES (?,?,?,?,?)', users_data)
conn.commit()
conn.close()

# 2. Setup JSON files
events_data = [
    {'session_id': 's1', 'user_id': 1, 'events': [{'type': 'purchase', 'amount': 50.0}]},
    {'session_id': 's2', 'user_id': 1, 'events': [{'type': 'purchase', 'amount': 100.0}]},
    {'session_id': 's3', 'user_id': 2, 'events': [{'type': 'purchase', 'amount': 200.0}]},
    {'session_id': 's4', 'user_id': 3, 'events': [{'type': 'purchase', 'amount': 300.0}]},
    {'session_id': 's5', 'user_id': 4, 'events': [{'type': 'purchase', 'amount': 250.0}]},
    {'session_id': 's6', 'user_id': 5, 'events': [{'type': 'purchase', 'amount': 1000.0}]},
    {'session_id': 's7', 'user_id': 6, 'events': [{'type': 'purchase', 'amount': 200.0}]},
    {'session_id': 's8', 'user_id': 7, 'events': [{'type': 'purchase', 'amount': 150.0}, {'type': 'purchase', 'amount': 50.0}]},
    {'session_id': 's9', 'user_id': 8, 'events': [{'type': 'purchase', 'amount': 220.0}]},
]

for i, ev in enumerate(events_data):
    with open(f'/home/user/data/events/event_{i}.json', 'w') as f:
        json.dump(ev, f)
"

    chmod -R 777 /home/user
