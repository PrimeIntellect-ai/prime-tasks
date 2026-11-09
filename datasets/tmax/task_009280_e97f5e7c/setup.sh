#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/warehouse.db <<EOF
CREATE TABLE authors (id INTEGER PRIMARY KEY, name TEXT, reputation INTEGER);
CREATE TABLE articles (id INTEGER PRIMARY KEY, author_id INTEGER, title TEXT, views INTEGER);
CREATE TABLE tags (article_id INTEGER, tag_name TEXT);

INSERT INTO authors (id, name, reputation) VALUES 
(1, 'Alice', 150),
(2, 'Bob', 90),
(3, 'Charlie', 200),
(4, 'Dave', 120);

INSERT INTO articles (id, author_id, title, views) VALUES 
(101, 1, 'Deep Learning Basics', 500),
(102, 2, 'Intro to C', 300),
(103, 3, 'Graph Databases', 800),
(104, 1, 'AI in Production', 600),
(105, 3, 'SQL Optimization', 400),
(106, 1, 'Future of AI', 700),
(107, 4, 'AI Ethics', 900),
(108, 4, 'AI Agents', 850),
(109, 3, 'AI for DBs', 950);

INSERT INTO tags (article_id, tag_name) VALUES 
(101, 'AI'), (101, 'ML'),
(102, 'C'),
(103, 'DB'), (103, 'Graph'),
(104, 'AI'), (104, 'Engineering'),
(105, 'DB'), (105, 'SQL'),
(106, 'AI'),
(107, 'AI'),
(108, 'AI'),
(109, 'AI');
EOF

    chmod -R 777 /home/user
