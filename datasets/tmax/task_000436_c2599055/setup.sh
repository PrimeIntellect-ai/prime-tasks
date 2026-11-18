#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import tarfile
import zipfile
import json
import csv

base_dir = "/home/user"
os.makedirs(base_dir, exist_ok=True)
os.chdir(base_dir)

# Create nested contents
v1_json = {"database": {"max_connections": 100, "host": "db.local"}}
v2_json = {"database": {"max_connections": 150, "host": "db.local"}}
v3_json = {"database": {"max_connections": 250, "host": "db.local"}}

csv_header = ["service_name", "port", "status"]
v1_csv = [["web_service", "80", "active"], ["cache_service", "6379", "active"]]
v2_csv = [["web_service", "80", "active"], ["cache_service", "6380", "active"]]
v3_csv = [["web_service", "80", "active"], ["cache_service", "6381", "active"]]

def create_files(ver_json, ver_csv):
    with open("app_config.json", "w") as f:
        json.dump(ver_json, f)
    with open("services.csv", "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(csv_header)
        writer.writerows(ver_csv)

# v1 (zip)
create_files(v1_json, v1_csv)
with zipfile.ZipFile("backup_v1.zip", "w") as zf:
    zf.write("app_config.json")
    zf.write("services.csv")

# v2 (tar.gz)
create_files(v2_json, v2_csv)
with tarfile.open("backup_v2.tar.gz", "w:gz") as tf:
    tf.add("app_config.json")
    tf.add("services.csv")

# v3 (zip)
create_files(v3_json, v3_csv)
with zipfile.ZipFile("backup_v3.zip", "w") as zf:
    zf.write("app_config.json")
    zf.write("services.csv")

# Clean up temp files
os.remove("app_config.json")
os.remove("services.csv")

# Create index.xml
xml_content = """<?xml version="1.0"?>
<backups>
    <version id="v1" file="backup_v1.zip" date="2023-10-01" />
    <version id="v2" file="backup_v2.tar.gz" date="2023-10-02" />
    <version id="v3" file="backup_v3.zip" date="2023-10-03" />
</backups>
"""
with open("index.xml", "w") as f:
    f.write(xml_content)

# Create master archive
with tarfile.open("config_backups.ccp", "w:gz") as master_tf:
    master_tf.add("index.xml")
    master_tf.add("backup_v1.zip")
    master_tf.add("backup_v2.tar.gz")
    master_tf.add("backup_v3.zip")

# Clean up intermediate archives
os.remove("index.xml")
os.remove("backup_v1.zip")
os.remove("backup_v2.tar.gz")
os.remove("backup_v3.zip")
EOF

    python3 /tmp/setup.py

    chmod -R 777 /home/user
