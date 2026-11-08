#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    python3 -c '
import csv
import os

data = [
    ["timestamp", "server_id", "log_level", "message"],
    ["2023-10-01T07:15:30Z", "srv1", "INFO", "Server started"],
    ["2023-10-01T08:10:00Z", "srv1", "ERROR", "DB connection failed\nTimeout on port 5432"],
    ["2023-10-01T08:12:00Z", "srv2", "ERROR", "DB connection failed\nTimeout on port 5432"],
    ["2023-10-01T08:15:00Z", "srv1", "ERROR", "DB connection failed\nTimeout on port 5432"],
    ["2023-10-01T08:20:00Z", "srv1", "ERROR", "Query failed"],
    ["2023-10-01T08:35:00Z", "srv1", "ERROR", "Out of memory"],
    ["2023-10-01T09:05:00Z", "srv1", "WARN", "High memory usage"],
    ["2023-10-01T09:10:00Z", "srv1", "WARN", "High CPU"],
    ["2023-10-01T09:15:00Z", "srv1", "WARN", "Disk space low"],
    ["2023-10-01T09:20:00Z", "srv1", "UNKNOWN", "Mysterious event"],
]

os.makedirs("/home/user", exist_ok=True)
with open("/home/user/app_logs.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerows(data)
'

    chmod -R 777 /home/user
