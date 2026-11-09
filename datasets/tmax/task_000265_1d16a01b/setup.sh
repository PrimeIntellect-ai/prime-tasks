#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c "
import sqlite3
import os

os.makedirs('/home/user', exist_ok=True)
db_path = '/home/user/social_data.db'
conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute('CREATE TABLE users (user_id INTEGER PRIMARY KEY, name TEXT)')
c.execute('CREATE TABLE friendships (user_id1 INTEGER, user_id2 INTEGER)')
c.execute('CREATE TABLE posts (post_id INTEGER PRIMARY KEY, user_id INTEGER, content TEXT)')
c.execute('CREATE TABLE engagements (post_id INTEGER PRIMARY KEY, likes INTEGER, shares INTEGER)')

users = [
    (1, 'Alice'), (2, 'Bob'), (3, 'Charlie'), (4, 'Diana'), 
    (5, 'Eve'), (6, 'Frank'), (7, 'Grace')
]
c.executemany('INSERT INTO users VALUES (?, ?)', users)

friendships = [
    (1, 2), (1, 3), (1, 4), 
    (2, 3),                 
    (4, 5), (4, 6),         
    (6, 7)                  
]
c.executemany('INSERT INTO friendships VALUES (?, ?)', friendships)

posts = [
    (101, 1, 'Hello world'), (102, 1, 'Post 2'),
    (103, 2, 'Bobs post'),
    (104, 3, 'Charlies post'),
    (105, 4, 'Dianas post'), (106, 4, 'Dianas second'),
    (107, 6, 'Franks post')
]
c.executemany('INSERT INTO posts VALUES (?, ?, ?)', posts)

engagements = [
    (101, 10, 5),  
    (102, 20, 10), 
    (103, 5, 2),   
    (104, 50, 25), 
    (105, 100, 50),
    (106, 0, 0),   
    (107, 2, 1)    
]
c.executemany('INSERT INTO engagements VALUES (?, ?, ?)', engagements)

conn.commit()
conn.close()
"

    chmod -R 777 /home/user
