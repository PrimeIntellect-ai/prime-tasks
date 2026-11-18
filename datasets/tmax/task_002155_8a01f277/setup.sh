#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import os

db_path = '/home/user/knowledge_graph.db'
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.executescript("""
CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE skills (id INTEGER PRIMARY KEY, skill_name TEXT);
CREATE TABLE user_skills (user_id INTEGER, skill_id INTEGER, FOREIGN KEY(user_id) REFERENCES users(id), FOREIGN KEY(skill_id) REFERENCES skills(id));
CREATE TABLE projects (id INTEGER PRIMARY KEY, title TEXT);
CREATE TABLE project_members (project_id INTEGER, user_id INTEGER, FOREIGN KEY(project_id) REFERENCES projects(id), FOREIGN KEY(user_id) REFERENCES users(id));

CREATE INDEX idx_user_skills_skill ON user_skills(skill_id);
CREATE INDEX idx_project_members_project ON project_members(project_id);
""")

users = [(1, 'Alice Smith'), (2, 'Bob Jones'), (3, 'Charlie Brown'), (4, 'Diana Prince'), (5, 'Evan Wright')]
skills = [(1, 'Python'), (2, 'Java'), (3, 'C++')]
user_skills = [(1, 1), (2, 1), (3, 1), (4, 1), (5, 2), (1, 2)]
projects = [(1, 'Alpha'), (2, 'Beta'), (3, 'Gamma'), (4, 'Delta')]
project_members = [
    (1, 1), (1, 2), (1, 3),
    (2, 1), (2, 2),
    (3, 3), (3, 4),
    (4, 1), (4, 4), (4, 3)
]

c.executemany("INSERT INTO users VALUES (?, ?)", users)
c.executemany("INSERT INTO skills VALUES (?, ?)", skills)
c.executemany("INSERT INTO user_skills VALUES (?, ?)", user_skills)
c.executemany("INSERT INTO projects VALUES (?, ?)", projects)
c.executemany("INSERT INTO project_members VALUES (?, ?)", project_members)

conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chmod -R 777 /home/user
