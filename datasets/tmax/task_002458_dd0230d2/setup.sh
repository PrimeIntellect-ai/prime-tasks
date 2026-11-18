#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/datasets/raw

    # Create the setup python script
    cat << 'EOF' > /tmp/setup.py
import os
import json

base_dir = "/home/user/datasets"
raw_dir = os.path.join(base_dir, "raw")
os.makedirs(raw_dir, exist_ok=True)

# File 1: data1.csv in ISO-8859-1
data1_content = "id,name,disease\n1,Müller,Cancer\n2,René,Diabetes\n"
data1_path = os.path.join(raw_dir, "data1.csv")
with open(data1_path, "w", encoding="iso-8859-1") as f:
    f.write(data1_content)

# File 2: data2.json in UTF-16LE
data2_content = '{"patients": [{"id": 3, "name": "José"}, {"id": 4, "name": "Åström"}]}'
data2_path = os.path.join(raw_dir, "data2.json")
with open(data2_path, "w", encoding="utf-16le") as f:
    f.write(data2_content)

# Metadata JSON
metadata = {
    "datasets": [
        {
            "source": "/home/user/datasets/raw/data1.csv",
            "original_encoding": "iso-8859-1",
            "alias": "clinical_trials_2023.csv"
        },
        {
            "source": "/home/user/datasets/raw/data2.json",
            "original_encoding": "utf-16le",
            "alias": "patient_records.json"
        }
    ]
}

metadata_path = os.path.join(base_dir, "metadata.json")
with open(metadata_path, "w", encoding="utf-8") as f:
    json.dump(metadata, f, indent=4)
EOF

    # Run the setup script
    python3 /tmp/setup.py
    rm /tmp/setup.py

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
