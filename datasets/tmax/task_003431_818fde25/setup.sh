#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3

conn = sqlite3.connect('/home/user/research_data.db')
cursor = conn.cursor()

cursor.execute('''CREATE TABLE papers (paper_id TEXT PRIMARY KEY, title TEXT, year INTEGER, field_of_study TEXT)''')
cursor.execute('''CREATE TABLE citations (citing_id TEXT, cited_id TEXT)''')

papers_data = [
    ('ROOT-01', 'Foundations of Everything', 2010, 'General'),
    ('A-01', 'AI Basic', 2015, 'Artificial Intelligence'),
    ('A-02', 'Deep Basic', 2016, 'Artificial Intelligence'),
    ('P-01', 'Physics Basic', 2015, 'Physics'),
    ('AI-20', 'Modern AI 1', 2020, 'Artificial Intelligence'),
    ('AI-21', 'Modern AI 2', 2021, 'Artificial Intelligence'),
    ('AI-22', 'Modern AI 3', 2022, 'Artificial Intelligence'),
    ('AI-23', 'Modern AI 4', 2022, 'Artificial Intelligence'),
    ('AI-24', 'Modern AI 5', 2023, 'Artificial Intelligence'),
    ('AI-25', 'Modern AI 6', 2023, 'Artificial Intelligence'),
    ('P-20', 'Modern Physics', 2020, 'Physics'),
]

citations_data = [
    ('A-01', 'ROOT-01'),
    ('P-01', 'ROOT-01'),
    ('A-02', 'A-01'),
    ('AI-20', 'A-02'),
    ('AI-21', 'A-01'),
    ('AI-22', 'AI-20'),
    ('AI-23', 'AI-21'),
    ('AI-24', 'AI-23'),
    ('AI-25', 'P-01'),
    ('P-20', 'P-01'),
    ('AI-23', 'AI-20')
]

cursor.executemany("INSERT INTO papers VALUES (?, ?, ?, ?)", papers_data)
cursor.executemany("INSERT INTO citations VALUES (?, ?)", citations_data)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
