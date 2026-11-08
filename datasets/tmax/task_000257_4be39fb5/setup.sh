#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest jsonschema

    useradd -m -s /bin/bash user || true

    python3 -c '
import sqlite3
import json
import os

os.makedirs("/home/user", exist_ok=True)

db_path = "/home/user/telemetry.db"
conn = sqlite3.connect(db_path)
cur = conn.cursor()

cur.execute("""
CREATE TABLE activity_logs (
    id INTEGER PRIMARY KEY,
    uid INTEGER NOT NULL,
    action VARCHAR(50) NOT NULL,
    created_at DATETIME NOT NULL
);
""")

events = [
    (1, 101, "login", "2023-10-01 10:00:00"),
    (2, 101, "view_item", "2023-10-01 10:05:00"),
    (3, 101, "checkout", "2023-10-01 10:15:00"),
    (4, 102, "checkout", "2023-10-01 10:20:00"),
    (5, 101, "logout", "2023-10-01 10:25:00"),
    (6, 103, "login", "2023-10-01 11:00:00"),
    (7, 103, "checkout", "2023-10-01 11:01:30"),
    (8, 104, "checkout", "2023-10-01 12:00:00")
]

cur.executemany("INSERT INTO activity_logs VALUES (?, ?, ?, ?)", events)

cur.execute("INSERT INTO activity_logs (id, uid, action, created_at) VALUES (9, \"bad_uid\", \"login\", \"2023-10-01 12:05:00\")")
cur.execute("INSERT INTO activity_logs (id, uid, action, created_at) VALUES (10, \"bad_uid\", \"checkout\", \"2023-10-01 12:10:00\")")

conn.commit()
conn.close()

schema = {
    "$schema": "http://json-schema.org/draft-07/schema#",
    "type": "object",
    "properties": {
        "user_id": {"type": "integer"},
        "event_id": {"type": "integer"},
        "timestamp": {"type": "string"},
        "seconds_since_last_event": {"type": ["integer", "null"]}
    },
    "required": ["user_id", "event_id", "timestamp", "seconds_since_last_event"],
    "additionalProperties": False
}

with open("/home/user/schema.json", "w") as f:
    json.dump(schema, f, indent=2)
'

    chmod -R 777 /home/user
