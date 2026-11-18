#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    python3 -c '
import csv
import json
import os

os.makedirs("/home/user", exist_ok=True)

csv_file = "/home/user/telemetry.csv"
json_file = "/home/user/users.json"

telemetry_data = [
    {"user_id": "u1", "event_type": "login", "timestamp": "2023-10-01T10:00:00Z", "region": "US"},
    {"user_id": "u2", "event_type": "click", "timestamp": "2023-10-01T10:05:00Z", "region": "EU"},
    {"user_id": "u3", "event_type": "view", "timestamp": "2023-10-01T10:10:00Z", "region": "US"},
    {"user_id": "u1", "event_type": "click", "timestamp": "2023-10-01T10:15:00Z", "region": "US"},
    {"user_id": "u4", "event_type": "login", "timestamp": "2023-10-01T10:20:00Z", "region": "AP"},
    {"user_id": "u2", "event_type": "logout", "timestamp": "2023-10-01T10:25:00Z", "region": "EU"},
    {"user_id": "u5", "event_type": "login", "timestamp": "2023-10-01T10:30:00Z", "region": "US"},
    {"user_id": "u3", "event_type": "logout", "timestamp": "2023-10-01T10:35:00Z", "region": "US"},
    {"user_id": "u4", "event_type": "click", "timestamp": "2023-10-01T10:40:00Z", "region": "AP"},
    {"user_id": "u6", "event_type": "view", "timestamp": "2023-10-01T10:45:00Z", "region": "EU"},
    {"user_id": "u1", "event_type": "logout", "timestamp": "2023-10-01T10:50:00Z", "region": "US"},
    {"user_id": "u5", "event_type": "view", "timestamp": "2023-10-01T10:55:00Z", "region": "US"}
]

with open(csv_file, "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=["user_id", "event_type", "timestamp", "region"])
    writer.writeheader()
    writer.writerows(telemetry_data)

users_data = [
    {"user_id": "u1", "subscription_tier": "Free"},
    {"user_id": "u2", "subscription_tier": "Premium"},
    {"user_id": "u3", "subscription_tier": "Basic"},
    {"user_id": "u4", "subscription_tier": "Free"},
    {"user_id": "u5", "subscription_tier": "Premium"}
]

with open(json_file, "w") as f:
    json.dump(users_data, f)
'

    chmod -R 777 /home/user
