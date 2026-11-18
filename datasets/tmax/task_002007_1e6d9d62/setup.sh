#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    # Create user
    useradd -m -s /bin/bash user || true

    # Generate initial state data
    python3 -c '
import os
import json
import csv

os.makedirs("/home/user/locales", exist_ok=True)

europe_data = [
    {"time": "2023-10-25T14:30:00+02:00", "locale": "fr-FR", "msg_id": "ERR_TIMEOUT"},
    {"time": "2023-10-25T14:45:00+02:00", "locale": "fr-FR", "msg_id": "ERR_TIMEOUT"},
    {"time": "2023-10-25T14:50:00+02:00", "locale": "fr-FR", "msg_id": "BTN_CANCEL"},
    {"time": "2023-10-25T15:10:00+02:00", "locale": "de-DE", "msg_id": "LBL_TITLE"},
    {"time": "2023-10-25T15:20:00+02:00", "locale": "de-DE", "msg_id": "LBL_TITLE"},
    {"time": "2023-10-25T15:30:00+02:00", "locale": "de-DE", "msg_id": "ERR_DB"}
]

with open("/home/user/locales/europe_logs.json", "w") as f:
    json.dump(europe_data, f)

asia_data = [
    {"timestamp": 1698237000, "locale": "ja-JP", "msg_id": "BTN_SUBMIT"},
    {"timestamp": 1698237100, "locale": "ja-JP", "msg_id": "BTN_SUBMIT"},
    {"timestamp": 1698237200, "locale": "ja-JP", "msg_id": "ERR_TIMEOUT"},
    {"timestamp": 1698240600, "locale": "ko-KR", "msg_id": "MENU_HELP"},
    {"timestamp": 1698240650, "locale": "ko-KR", "msg_id": "MENU_HELP"},
    {"timestamp": 1698240650, "locale": "ko-KR", "msg_id": "MENU_HELP"}
]

with open("/home/user/locales/asia_logs.csv", "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=["timestamp", "locale", "msg_id"])
    writer.writeheader()
    for row in asia_data:
        writer.writerow(row)
'

    chmod -R 777 /home/user
