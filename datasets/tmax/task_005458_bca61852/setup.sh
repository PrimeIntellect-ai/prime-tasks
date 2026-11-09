#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    python3 -c "
import sqlite3
import os

os.makedirs('/home/user', exist_ok=True)
db_path = '/home/user/research_data.db'

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

cursor.execute('''CREATE TABLE subjects (sub_id INTEGER PRIMARY KEY, name TEXT, age INTEGER)''')
cursor.execute('''CREATE TABLE trial_runs (trial_id INTEGER PRIMARY KEY, subject_id INTEGER, date TEXT, condition TEXT)''')
cursor.execute('''CREATE TABLE sensor_data (meas_id INTEGER PRIMARY KEY, t_id INTEGER, sensor TEXT, value REAL)''')

subjects = [(1, 'Alice', 28), (2, 'Bob', 35)]
trials = [(101, 1, '2023-01-01', 'Control'), (102, 1, '2023-01-02', 'Treatment'), (103, 2, '2023-01-01', 'Treatment')]
measurements = [(1001, 101, 'HeartRate', 72.5), (1002, 101, 'Temp', 98.6), (1003, 102, 'HeartRate', 85.0), (1004, 103, 'HeartRate', 78.2)]

cursor.executemany('INSERT INTO subjects VALUES (?, ?, ?)', subjects)
cursor.executemany('INSERT INTO trial_runs VALUES (?, ?, ?, ?)', trials)
cursor.executemany('INSERT INTO sensor_data VALUES (?, ?, ?, ?)', measurements)

conn.commit()
conn.close()
"

    chmod -R 777 /home/user
