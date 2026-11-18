#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas lxml

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import json
import csv
import xml.etree.ElementTree as ET

os.makedirs('/home/user/loc_data', exist_ok=True)

# run1.json
run1_data = [
    {"src": "  Hello World  ", "lang": "es", "trans": "Hola Mundo", "ts": 1697090000},
    {"src": "Login\u00A0", "lang": "fr", "trans": "Connexion", "ts": 1697090100},
    {"src": "Error: Not found", "lang": "de", "trans": "Fehler: Nicht gefunden", "ts": 1697090200}
]
with open('/home/user/loc_data/run1.json', 'w') as f:
    json.dump(run1_data, f)

# run2_retry.csv
run2_data = [
    ["source_text", "target_lang", "translation", "timestamp"],
    ["hello world", "es", "Hola mundo!", "2023-10-12T05:55:00Z"], # ts: 1697090100 (newer than run1)
    ["Cancel", "es", "Cancelar", "2023-10-12T06:00:00Z"], # ts: 1697090400
    ["  login  ", "fr", "Se connecter", "2023-10-12T05:50:00Z"] # ts: 1697089800 (older than run1)
]
with open('/home/user/loc_data/run2_retry.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerows(run2_data)

# manual_fixes.xml
root = ET.Element("translations")
# Newer timestamp for login fr -> ts: 1697091000
record1 = ET.SubElement(root, "record")
ET.SubElement(record1, "source").text = "Login"
ET.SubElement(record1, "lang").text = "fr"
ET.SubElement(record1, "translated").text = "Identifier"
ET.SubElement(record1, "time").text = "1697091000"

# New string
record2 = ET.SubElement(root, "record")
ET.SubElement(record2, "source").text = "Submit"
ET.SubElement(record2, "lang").text = "de"
ET.SubElement(record2, "translated").text = "Einreichen"
ET.SubElement(record2, "time").text = "1697091500"

tree = ET.ElementTree(root)
tree.write('/home/user/loc_data/manual_fixes.xml')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
