#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx pandas jsonschema

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_data.py
import sqlite3
import json

db_path = "/home/user/papers.db"
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# Create tables
cursor.executescript('''
CREATE TABLE papers (id INTEGER PRIMARY KEY, title TEXT, year INTEGER);
CREATE TABLE authors (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE paper_authors (paper_id INTEGER, author_id INTEGER, FOREIGN KEY(paper_id) REFERENCES papers(id), FOREIGN KEY(author_id) REFERENCES authors(id));
CREATE TABLE citations (source_paper_id INTEGER, target_paper_id INTEGER, FOREIGN KEY(source_paper_id) REFERENCES papers(id), FOREIGN KEY(target_paper_id) REFERENCES papers(id));
''')

# Insert data
papers = [
    (1, "A", 1992), (2, "B", 1995), (3, "C", 1998), 
    (4, "D", 2001), (5, "E", 2005), (6, "F", 2009),
    (7, "G", 2011), (8, "H", 2015), (9, "I", 2019),
    (10, "J", 2020)
]
cursor.executemany("INSERT INTO papers VALUES (?, ?, ?)", papers)

authors = [
    (1, "Alice"), (2, "Bob"), (3, "Charlie"), (4, "Diana"), (5, "Eve")
]
cursor.executemany("INSERT INTO authors VALUES (?, ?)", authors)

paper_authors = [
    (1, 1), (1, 2), # Alice & Bob
    (2, 1), (3, 1), # Alice
    (4, 2), (5, 2), (6, 2), # Bob
    (7, 3), (8, 3), (8, 4), # Charlie & Diana
    (9, 4), (10, 4), # Diana
    (10, 5) # Eve
]
cursor.executemany("INSERT INTO paper_authors VALUES (?, ?)", paper_authors)

citations = [
    (2, 1), (3, 1), (4, 1), (5, 2), (6, 2),
    (7, 4), (8, 4), (9, 7), (10, 8)
]
cursor.executemany("INSERT INTO citations VALUES (?, ?)", citations)

conn.commit()
conn.close()

# Create JSON Schema
schema = {
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "array",
  "items": {
    "type": "object",
    "properties": {
      "author_id": {"type": "integer"},
      "author_name": {"type": "string"},
      "peak_decade": {"type": "integer"},
      "author_score": {"type": "number"},
      "decade_rank": {"type": "integer", "minimum": 1, "maximum": 3},
      "max_coauthor_weight": {"type": "integer"}
    },
    "required": ["author_id", "author_name", "peak_decade", "author_score", "decade_rank", "max_coauthor_weight"]
  }
}

with open("/home/user/output_schema.json", "w") as f:
    json.dump(schema, f, indent=2)

EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    chmod -R 777 /home/user
