#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest python-dateutil pytz

    # Create user
    useradd -m -s /bin/bash user || true

    # Generate initial data
    python3 << 'EOF'
import os
import csv

base_dir = "/home/user/loc_servers"
servers = ["eu-west", "us-east", "ap-south"]

for server in servers:
    os.makedirs(os.path.join(base_dir, server), exist_ok=True)

eu_data = [
    ["timestamp", "lang_code", "original_text", "translated_text"],
    ["2023-11-01 14:30:00+02:00", "fr-FR", "Welcome", "Bienvenue"],
    ["2023-11-01 15:00:00+02:00", "de-DE", "Multi\nLine\nTest", "Mehrzeiliger\nTest\nHier"]
]

us_data = [
    ["timestamp", "lang_code", "original_text", "translated_text"],
    ["2023-11-01 12:30:00Z", "es-ES", "Settings", "Ajustes"],
    ["2023-11-01 12:45:00-04:00", "es-MX", "Error occurred", "Ocurrió un error\nPor favor intente de nuevo"]
]

ap_data = [
    ["timestamp", "lang_code", "original_text", "translated_text"],
    ["2023-11-01 21:00:00+05:30", "hi-IN", "Submit", "प्रस्तुत"],
    ["2023-11-01 22:15:00+09:00", "ja-JP", "Warning:\nLow Battery", "警告:\nバッテリー低下"]
]

with open(f"{base_dir}/eu-west/updates.csv", "w", newline="", encoding="utf-8") as f:
    csv.writer(f).writerows(eu_data)

with open(f"{base_dir}/us-east/updates.csv", "w", newline="", encoding="utf-8") as f:
    csv.writer(f).writerows(us_data)

with open(f"{base_dir}/ap-south/updates.csv", "w", newline="", encoding="utf-8") as f:
    csv.writer(f).writerows(ap_data)
EOF

    chmod -R 777 /home/user
