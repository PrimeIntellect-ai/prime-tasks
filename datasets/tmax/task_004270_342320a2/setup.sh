#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/activity.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('CREATE TABLE users (user_id INTEGER PRIMARY KEY, name TEXT)')
c.execute('CREATE TABLE posts (post_id INTEGER PRIMARY KEY, author_id INTEGER, content TEXT)')
c.execute('CREATE TABLE comments (comment_id INTEGER PRIMARY KEY, post_id INTEGER, commenter_id INTEGER, content TEXT)')

# Insert Users
users = [(1, 'Alice'), (2, 'Bob'), (3, 'Charlie'), (4, 'Diana'), (5, 'Eve')]
c.executemany('INSERT INTO users VALUES (?, ?)', users)

# Insert Posts
posts = [
    (101, 1, 'Post 1 by Alice'),
    (102, 2, 'Post 2 by Bob'),
    (103, 1, 'Post 3 by Alice'),
    (104, 3, 'Post 4 by Charlie'),
    (105, 5, 'Post 5 by Eve')
]
c.executemany('INSERT INTO posts VALUES (?, ?, ?)', posts)

# Insert Comments
comments = [
    (1001, 101, 2, 'Comment by Bob on Alice'),
    (1002, 101, 2, 'Comment by Bob on Alice'),
    (1003, 102, 1, 'Comment by Alice on Bob'),
    (1004, 103, 3, 'Charlie on Alice'),
    (1005, 104, 3, 'Self comment'),
    (1006, 105, 2, 'Bob on Eve'),
    (1007, 101, 5, 'Eve on Alice'),
    (1008, 101, 5, 'Eve on Alice again'),
    (1009, 103, 5, 'Eve on Alice third time')
]
c.executemany('INSERT INTO comments VALUES (?, ?, ?, ?)', comments)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
