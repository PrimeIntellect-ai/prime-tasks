#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import sqlite3
import json
import os

db_path = "/home/user/research_data.db"
schema_path = "/home/user/trial_schema.json"

# Create SQLite DB
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

cursor.execute('''CREATE TABLE sites (id INTEGER PRIMARY KEY, name TEXT, location TEXT)''')
cursor.execute('''CREATE TABLE subjects (id INTEGER PRIMARY KEY, site_id INTEGER, age INTEGER, group_name TEXT)''')
cursor.execute('''CREATE TABLE trials (id INTEGER PRIMARY KEY, subject_id INTEGER, date TEXT, outcome TEXT, score REAL)''')

sites_data = [
    (1, 'Alpha Lab', 'New York'),
    (2, 'Beta Clinic', 'London')
]
subjects_data = [
    (101, 1, 45, 'Control'),
    (102, 1, 38, 'Treatment A'),
    (103, 2, 50, 'Treatment B')
]
trials_data = [
    (1001, 101, '2023-10-01', 'Success', 85.5),
    (1002, 101, '2023-10-15', 'Failure', 42.0),
    (1003, 102, '2023-11-02', 'Success', 91.2),
    (1004, 103, '2023-11-10', 'Partial', 68.9)
]

cursor.executemany("INSERT INTO sites VALUES (?, ?, ?)", sites_data)
cursor.executemany("INSERT INTO subjects VALUES (?, ?, ?, ?)", subjects_data)
cursor.executemany("INSERT INTO trials VALUES (?, ?, ?, ?, ?)", trials_data)
conn.commit()
conn.close()

# Create JSON Schema
schema = {
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "array",
  "items": {
    "type": "object",
    "properties": {
      "trial_id": {"type": "integer"},
      "date": {"type": "string"},
      "outcome": {"type": "string"},
      "score": {"type": "number"},
      "subject": {
        "type": "object",
        "properties": {
          "subject_id": {"type": "integer"},
          "age": {"type": "integer"},
          "cohort_group": {"type": "string"},
          "site": {
            "type": "object",
            "properties": {
              "site_id": {"type": "integer"},
              "name": {"type": "string"},
              "location": {"type": "string"}
            },
            "required": ["site_id", "name", "location"]
          }
        },
        "required": ["subject_id", "age", "cohort_group", "site"]
      }
    },
    "required": ["trial_id", "date", "outcome", "score", "subject"]
  }
}

with open(schema_path, "w") as f:
    json.dump(schema, f, indent=2)

EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py
    chmod -R 777 /home/user
